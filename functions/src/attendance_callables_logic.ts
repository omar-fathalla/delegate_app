/**
 * TAS-361 (phase 2): the decisions behind delegateCheckIn / delegateCheckOut.
 *
 * The app used to write attendance_logs itself and to run every check on the
 * phone. The callables move the checks to the server: the branch comes from
 * Firestore (never from the request), the distance uses radius + 50 m, one
 * open session per delegate, the same branch at most once per Cairo day, and
 * the identity comes from the token. A check-out is never refused for the
 * distance; it is flagged (checkOutOutsideBranch) for HR.
 *
 * Limits: the position is still the one the phone sends (fake GPS: TAS-372).
 */
import {
  GEOFENCE_TOLERANCE_METERS,
  branchGeofence,
  haversineMeters,
} from "./delegate_tracking_verify_logic";

/** Same window the app and HR screens use for a forgotten session. */
export const OPEN_SESSION_WINDOW_MS = (11 * 60 + 30) * 60 * 1000;

export type Doc = Record<string, unknown> | null | undefined;

/** Machine-readable refusal; the app picks its Arabic message from it. */
export type AttendanceReason =
  | "not_delegate"
  | "bad_request"
  | "no_branch"
  | "branch_not_found"
  | "branch_without_location"
  | "branch_other_chain"
  | "not_member"
  | "no_position"
  | "outside_branch"
  | "open_session_same_branch"
  | "open_session_other_branch"
  | "same_branch_today"
  | "record_not_found"
  | "not_owner"
  | "already_checked_out";

export interface Refusal {
  ok: false;
  reason: AttendanceReason;
  /** Arabic text the app may show as is. */
  message: string;
  distanceMeters?: number;
  allowedMeters?: number;
  branchName?: string;
}

export const MESSAGES: Record<AttendanceReason, string> = {
  not_delegate: "تسجيل الحضور للمناديب بس.",
  bad_request: "البيانات اللي اتبعتت ناقصة. حدّث التطبيق وجرّب تاني.",
  no_branch: "اختار الفرع الأول.",
  branch_not_found: "الفرع ده مش موجود. اتأكد من الكود أو كلّم المشرف.",
  branch_without_location: "مكان الفرع مش متسجل في النظام. بلّغ المشرف.",
  branch_other_chain: "الفرع ده تبع سلسلة إنت مش فيها.",
  not_member: "إنت مش مسجل في الشركة دي. كلّم المشرف.",
  no_position: "مش قادرين نحدد مكانك. شغّل الـ GPS وجرّب تاني.",
  outside_branch: "إنت برّه نطاق الفرع.",
  open_session_same_branch: "إنت مسجل حضور في الفرع ده بالفعل، والجلسة لسه مفتوحة.",
  open_session_other_branch: "عندك حضور مفتوح في فرع تاني. سجّل انصراف الأول.",
  same_branch_today: "ماينفعش تسجل حضور في نفس الفرع مرتين في نفس اليوم.",
  record_not_found: "سجل الحضور مش موجود.",
  not_owner: "سجل الحضور ده مش بتاعك.",
  already_checked_out: "إنت سجلت انصراف بالفعل.",
};

export function refuse(reason: AttendanceReason, extra: Partial<Refusal> = {}): Refusal {
  return {ok: false, reason, message: MESSAGES[reason], ...extra};
}

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** Org ids the delegate token names (claims `orgId` + `orgIds`). */
export function tokenOrgIds(token: Doc): string[] {
  const t = token || {};
  const list = Array.isArray(t.orgIds) ? t.orgIds.map(str) : [];
  return [...new Set([str(t.orgId), ...list].filter(Boolean))];
}

export function isDelegateToken(token: Doc): boolean {
  return str((token || {}).role) === "delegate";
}

const ID_RE = /^[A-Za-z0-9_-]{6,128}$/;

export interface CheckInInput {
  branchId: string;
  branchOrganizationUID: string;
  organizationId: string;
  companyId: string;
  lat: number | null;
  lng: number | null;
  requestId: string;
  deviceInfo: string;
  branchName: string;
  delegateName: string;
  phoneNumber: string;
  companyName: string;
  personalPhotoURL: string;
}

/** Validates the request shape. Everything trusted is re-read on the server. */
export function parseCheckIn(data: unknown): CheckInInput | Refusal {
  const d = (data && typeof data === "object") ? data as Record<string, unknown> : {};
  const organizationId = str(d.organizationId);
  const companyId = str(d.companyId);
  const requestId = str(d.requestId);
  if (!organizationId || !companyId || !ID_RE.test(requestId)) return refuse("bad_request");
  const branchId = str(d.branchId);
  if (!branchId) return refuse("no_branch");
  return {
    branchId,
    branchOrganizationUID: str(d.branchOrganizationUID) || organizationId,
    organizationId,
    companyId,
    lat: num(d.lat),
    lng: num(d.lng),
    requestId,
    deviceInfo: str(d.deviceInfo).slice(0, 300),
    branchName: str(d.branchName).slice(0, 200),
    delegateName: str(d.delegateName).slice(0, 200),
    phoneNumber: str(d.phoneNumber).slice(0, 30),
    companyName: str(d.companyName).slice(0, 200),
    personalPhotoURL: str(d.personalPhotoURL).slice(0, 1000),
  };
}

export interface CheckOutInput {
  attendanceId: string;
  lat: number | null;
  lng: number | null;
}

export function parseCheckOut(data: unknown): CheckOutInput | Refusal {
  const d = (data && typeof data === "object") ? data as Record<string, unknown> : {};
  const attendanceId = str(d.attendanceId);
  if (!ID_RE.test(attendanceId)) return refuse("bad_request");
  return {attendanceId, lat: num(d.lat), lng: num(d.lng)};
}

function validPos(lat: number | null, lng: number | null): boolean {
  if (lat == null || lng == null) return false;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
  return !(lat === 0 && lng === 0);
}

/** Calendar day in Cairo (Africa/Cairo, DST-aware), e.g. "2026-11-27". */
export function cairoDay(ms: number): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date(ms));
}

/** A recent attendance record of the caller, reduced to what the rules use. */
export interface RecentLog {
  id: string;
  type: string;
  /** Check-in time in ms (server timestamp), or null while pending. */
  atMs: number | null;
  branchId: string;
  branchOrganizationUID: string;
  branchName: string;
  closed: boolean;
}

export function toRecentLog(id: string, data: Doc, toMs: (v: unknown) => number | null): RecentLog {
  const d = data || {};
  return {
    id,
    type: str(d.type),
    atMs: toMs(d.timestamp),
    branchId: str(d.branchId),
    branchOrganizationUID: str(d.branchOrganizationUID) || str(d.organizationId),
    branchName: str(d.branchName),
    closed: d.checkOutTime != null || d.isAutoCheckOut === true || d.missingCheckOut === true,
  };
}

function sameBranch(log: RecentLog, input: CheckInInput): boolean {
  if (log.branchId) {
    return log.branchId === input.branchId &&
      (!log.branchOrganizationUID || log.branchOrganizationUID === input.branchOrganizationUID);
  }
  // Legacy logs without branchId: compare the stored name.
  return !!log.branchName && log.branchName === input.branchName;
}

export interface CheckInDecisionInput {
  input: CheckInInput;
  token: Doc;
  /** organizations/{org}/companies/{co}/delegates/{delegateId}, or null. */
  membership: Doc;
  /** The branch as stored (nested under its chain, then root), or null. */
  branch: Doc;
  /** The caller's latest attendance records (newest first). */
  recent: RecentLog[];
  nowMs: number;
}

export interface CheckInAccepted {
  ok: true;
  distanceMeters: number;
  allowedMeters: number;
}

/** Every check a check-in must pass, in the order the app shows them. */
export function decideCheckIn(x: CheckInDecisionInput): CheckInAccepted | Refusal {
  const {input} = x;
  if (!isDelegateToken(x.token)) return refuse("not_delegate");
  const orgs = tokenOrgIds(x.token);
  if (!orgs.includes(input.organizationId) || !orgs.includes(input.branchOrganizationUID)) {
    return refuse("branch_other_chain");
  }
  const status = str((x.membership || {}).status).toLowerCase();
  if (!x.membership || ["deleted", "removed", "archived"].includes(status)) return refuse("not_member");

  // One open session per delegate, whatever the day (a session older than
  // the auto-close window is a forgotten one: TAS-362 closes it).
  const open = x.recent.find((l) => l.type === "check_in" && !l.closed &&
    (l.atMs == null || x.nowMs - l.atMs < OPEN_SESSION_WINDOW_MS));
  if (open) {
    return sameBranch(open, input) ?
      refuse("open_session_same_branch") :
      refuse("open_session_other_branch", {branchName: open.branchName || undefined});
  }
  const today = cairoDay(x.nowMs);
  if (x.recent.some((l) => l.type === "check_in" && l.atMs != null &&
    cairoDay(l.atMs) === today && sameBranch(l, input))) {
    return refuse("same_branch_today");
  }

  if (!x.branch) return refuse("branch_not_found");
  const fence = branchGeofence(x.branch);
  if (!fence) return refuse("branch_without_location");
  if (!validPos(input.lat, input.lng)) return refuse("no_position");
  const distance = haversineMeters(input.lat as number, input.lng as number, fence.lat, fence.lng);
  const allowed = fence.radius + GEOFENCE_TOLERANCE_METERS;
  if (distance > allowed) {
    return refuse("outside_branch", {
      distanceMeters: Math.round(distance),
      allowedMeters: Math.round(allowed),
      message: `إنت برّه نطاق الفرع (${Math.round(distance)} متر). المسموح ${Math.round(allowed)} متر.`,
    });
  }
  return {ok: true, distanceMeters: Math.round(distance * 10) / 10, allowedMeters: allowed};
}

/** The check-in record the server writes (timestamp added by the caller). */
export function buildCheckInDoc(input: CheckInInput, delegateId: string): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    delegateId,
    userId: delegateId,
    companyId: input.companyId,
    organizationId: input.organizationId,
    type: "check_in",
    location: {latitude: input.lat, longitude: input.lng},
    deviceInfo: input.deviceInfo,
    branchName: input.branchName,
    branchId: input.branchId,
    branchOrganizationUID: input.branchOrganizationUID,
    source: "server",
  };
  if (input.delegateName) doc.delegateName = input.delegateName;
  if (input.phoneNumber) doc.phoneNumber = input.phoneNumber;
  if (input.companyName) doc.companyName = input.companyName;
  if (input.personalPhotoURL) doc.personalPhotoURL = input.personalPhotoURL;
  return doc;
}

export interface CheckOutDecisionInput {
  attendanceId: string;
  record: Doc;
  /** Every id that names the caller (uid + delegateId claim). */
  selfIds: string[];
  token: Doc;
}

export type CheckOutDecision =
  | {ok: true; already: boolean}
  | Refusal;

/** Ownership and state; the distance never refuses a check-out. */
export function decideCheckOut(x: CheckOutDecisionInput): CheckOutDecision {
  if (!isDelegateToken(x.token)) return refuse("not_delegate");
  if (!x.record) return refuse("record_not_found");
  const r = x.record;
  if (str(r.type) && str(r.type) !== "check_in") return refuse("record_not_found");
  const owner = [str(r.delegateId), str(r.userId)].filter(Boolean);
  if (!owner.some((id) => x.selfIds.includes(id))) return refuse("not_owner");
  if (r.checkOutTime != null) {
    // A retry after a timeout whose first attempt landed: same result.
    if (str(r.checkOutDocId) === `${x.attendanceId}_out`) return {ok: true, already: true};
    return refuse("already_checked_out");
  }
  return {ok: true, already: false};
}

/** Distance of the check-out, for the response and the flag. */
export function checkOutDistance(lat: number | null, lng: number | null, branch: Doc):
  {distanceMeters: number | null; outside: boolean} {
  const fence = branchGeofence(branch);
  if (!fence || !validPos(lat, lng)) return {distanceMeters: null, outside: false};
  const d = haversineMeters(lat as number, lng as number, fence.lat, fence.lng);
  return {distanceMeters: Math.round(d * 10) / 10, outside: d > fence.radius + GEOFENCE_TOLERANCE_METERS};
}
