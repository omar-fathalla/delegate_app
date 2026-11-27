/**
 * TAS-361 (phase 1): server check of attendance_logs documents.
 *
 * The delegate's app writes check-in / check-out records itself, and the only
 * distance check is in the app (a check-out from anywhere passes, TAS-361).
 * The trigger recomputes the distance from the stored branch and stamps
 * server-only fields so HR sees a check-out made outside the branch. Nothing
 * is rejected: old app builds keep working (the rules lock comes later, after
 * the callables and the min-version gate).
 *
 * Limits: the position is still the one the phone sent, so a faked GPS is not
 * caught here (TAS-372).
 */
import {
  GEOFENCE_TOLERANCE_METERS,
  branchGeofence,
  haversineMeters,
} from "./delegate_tracking_verify_logic";

/** Fields only the trigger writes on an attendance record. */
export const ATTENDANCE_SERVER_FIELDS = [
  "verifiedDistanceMeters",
  "verifiedInsideBranch",
  "verifiedBranchRadius",
  "verifiedReason",
  "verifiedFor",
  "verifiedAt",
  "checkOutVerifiedDistanceMeters",
  "checkOutOutsideBranch",
  "checkOutVerifiedReason",
  "checkOutVerifiedFor",
  "checkOutVerifiedAt",
];

export type AttendanceVerifiedReason =
  | "ok"
  | "no_position"
  | "no_branch"
  | "branch_not_found"
  | "branch_without_location";

type Doc = Record<string, unknown> | null | undefined;

export interface PositionCheck {
  distanceMeters: number | null;
  inside: boolean | null;
  radius: number | null;
  reason: AttendanceVerifiedReason;
}

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function coord(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** {latitude|lat, longitude|lng} map, or null when it is not a real pair. */
export function readPosition(value: unknown): {lat: number; lng: number} | null {
  if (!value || typeof value !== "object") return null;
  const m = value as Record<string, unknown>;
  const lat = coord(m.latitude) ?? coord(m.lat);
  const lng = coord(m.longitude) ?? coord(m.lng);
  if (lat == null || lng == null) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  if (lat === 0 && lng === 0) return null;
  return {lat, lng};
}

/** Where the branch lives: nested under its chain first, then root branches. */
export function branchRef(data: Doc): {branchId: string; organizationUID: string} {
  const d = data || {};
  return {
    branchId: str(d.branchId),
    organizationUID: str(d.branchOrganizationUID) || str(d.organizationId) || str(d.organizationUID),
  };
}

/** The check-in position (or the position of a type == check_out record). */
export function checkInPosition(data: Doc): {lat: number; lng: number} | null {
  return readPosition((data || {}).location);
}

/** The check-out position stamped on the check-in record. */
export function checkOutPosition(data: Doc): {lat: number; lng: number} | null {
  return readPosition((data || {}).checkOutLocation);
}

/** A stable key of what a verdict was computed from (loop guard). */
export function signature(pos: {lat: number; lng: number} | null, data: Doc): string {
  const b = branchRef(data);
  return [pos ? `${pos.lat},${pos.lng}` : "-", b.organizationUID, b.branchId].join("|");
}

export function checkPosition(pos: {lat: number; lng: number} | null, data: Doc, branch: Doc): PositionCheck {
  const none = {distanceMeters: null, inside: null, radius: null};
  if (!pos) return {...none, reason: "no_position"};
  if (!branchRef(data).branchId) return {...none, reason: "no_branch"};
  if (!branch) return {...none, reason: "branch_not_found"};
  const fence = branchGeofence(branch);
  if (!fence) return {...none, reason: "branch_without_location"};
  const distance = haversineMeters(pos.lat, pos.lng, fence.lat, fence.lng);
  return {
    distanceMeters: Math.round(distance * 10) / 10,
    inside: distance <= fence.radius + GEOFENCE_TOLERANCE_METERS,
    radius: fence.radius,
    reason: "ok",
  };
}

export interface AttendancePlan {
  /** Recompute the check-in (or check_out record) position verdict. */
  checkIn: boolean;
  /** Recompute the check-out verdict stamped on a check-in record. */
  checkOut: boolean;
}

function isCheckOutRecord(data: Doc): boolean {
  return str((data || {}).type) === "check_out";
}

/**
 * What to (re)compute. On create everything is computed, so a client cannot
 * plant a verdict (or a matching verifiedFor) in its own new record. After
 * that, a part is recomputed only when its inputs no longer match the stored
 * signature; the trigger's own write keeps the signature equal, so it stops.
 */
export function planVerification(before: Doc, after: Doc): AttendancePlan {
  if (!after) return {checkIn: false, checkOut: false};
  const created = !before;
  const out = isCheckOutRecord(after);
  const checkIn = created || str(after.verifiedFor) !== signature(checkInPosition(after), after);
  const hasCheckOut = !out && (checkOutPosition(after) != null || after.checkOutTime != null);
  const checkOut = !out && (
    (created && (hasCheckOut || after.checkOutVerifiedFor != null || after.checkOutOutsideBranch != null)) ||
    (hasCheckOut && str(after.checkOutVerifiedFor) !== signature(checkOutPosition(after), after))
  );
  return {checkIn, checkOut};
}

/** The update the trigger writes (without the server timestamps). */
export function verificationUpdate(after: Doc, plan: AttendancePlan, branch: Doc): Record<string, unknown> {
  const update: Record<string, unknown> = {};
  if (plan.checkIn) {
    const pos = checkInPosition(after);
    const c = checkPosition(pos, after, branch);
    update.verifiedDistanceMeters = c.distanceMeters;
    update.verifiedInsideBranch = c.inside;
    update.verifiedBranchRadius = c.radius;
    update.verifiedReason = c.reason;
    update.verifiedFor = signature(pos, after);
    // A type == check_out record is itself a check-out: flag it too.
    if (isCheckOutRecord(after)) update.checkOutOutsideBranch = c.inside === false;
  }
  if (plan.checkOut) {
    const pos = checkOutPosition(after);
    if (!pos && after?.checkOutTime == null) {
      // Created with planted check-out verdict fields and no check-out.
      update.checkOutVerifiedDistanceMeters = null;
      update.checkOutOutsideBranch = null;
      update.checkOutVerifiedReason = null;
      update.checkOutVerifiedFor = null;
    } else {
      const c = checkPosition(pos, after, branch);
      update.checkOutVerifiedDistanceMeters = c.distanceMeters;
      update.checkOutOutsideBranch = c.inside === false;
      update.checkOutVerifiedReason = c.reason;
      update.checkOutVerifiedFor = signature(pos, after);
    }
  }
  return update;
}
