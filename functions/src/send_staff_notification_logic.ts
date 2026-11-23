/**
 * Pure helpers for sendStaffNotification (TAS-216).
 *
 * The send-notification screen used to search phones, list users by role and
 * read every delegate from the client. The hardened rules deny that for
 * anyone who is not global staff. The callable does it with the Admin SDK and
 * keeps every recipient inside the caller's scope, which is read from
 * users/{uid} on the server and never taken from the request.
 */
import {normalizePhone, phoneQueryVariants} from "./delegate_login_logic";
import {normalizeRoleKey} from "./staff_phone_lookup_logic";

/** Hard cap on notification docs one call may write. */
export const MAX_RECIPIENTS = 2000;
/** Firestore allows 500 writes per batch; stay well under it. */
export const BATCH_SIZE = 450;
export const MAX_TITLE_LENGTH = 200;
export const MAX_BODY_LENGTH = 2000;
export const NOTIFICATION_TYPES = ["update", "announcement", "support_alert"] as const;

export type CallerScope =
  | {kind: "global"}
  | {kind: "org"; org: string}
  | {kind: "company"; org: string; company: string};

export type NotifyTarget =
  | {kind: "all"}
  | {kind: "org"; org: string}
  | {kind: "company"; org: string; company: string}
  | {kind: "role"; role: string}
  | {kind: "user"; phone: string; uid: string};

export type Denial = {ok: false; code: DenialCode; reason: string; message: string};
export type DenialCode =
  | "permission-denied"
  | "invalid-argument"
  | "failed-precondition";

function deny(code: DenialCode, reason: string, message: string): Denial {
  return {ok: false, code, reason, message};
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

const GLOBAL_ROLES = new Set([
  "super_admin", "superadmin",
  "technical_support", "technicalsupport", "tech_support", "techsupport",
]);
const ORG_ROLES = new Set(["organization_admin", "organizationadmin"]);
const MARKETING_ROLES = new Set(["marketing", "marketing_promotion", "marketingpromotion"]);
const COMPANY_ROLES = new Set([
  "company_admin", "companyadmin", "admin", "supervisor", "company_supervisor",
  "hr", "company_hr", "human_resources",
  "accountant", "accounting", "account_admin",
  "branches_marketing", "branches_marketing_manager", "branchesmarketingmanager",
]);

/** camelCase role keys ("superAdmin") become "superadmin" after normalizeRoleKey. */
function roleKey(role: unknown): string {
  return normalizeRoleKey(role);
}

/**
 * Caller scope from the server-side users doc. A delegate token, a missing
 * users doc, an unknown role, or a scoped role without its org/company is
 * rejected.
 */
export function callerScopeFrom(
  user: Record<string, unknown> | null | undefined,
  tokenRole: unknown,
): CallerScope | Denial {
  if (str(tokenRole).toLowerCase() === "delegate") {
    return deny("permission-denied", "delegate_not_allowed", "Delegates cannot send notifications.");
  }
  if (!user) return deny("permission-denied", "no_profile", "Staff profile not found.");
  const role = roleKey(user.role);
  const org = str(user.organizationUID) || str(user.organizationId);
  const company = str(user.companyUID) || str(user.companyId);
  if (GLOBAL_ROLES.has(role)) return {kind: "global"};
  if (ORG_ROLES.has(role)) {
    return org ? {kind: "org", org} : deny("permission-denied", "no_scope", "Organization is missing.");
  }
  if (MARKETING_ROLES.has(role)) {
    if (company && org) return {kind: "company", org, company};
    if (org) return {kind: "org", org};
    return deny("permission-denied", "no_scope", "Organization is missing.");
  }
  if (COMPANY_ROLES.has(role)) {
    return company && org ?
      {kind: "company", org, company} :
      deny("permission-denied", "no_scope", "Company is missing.");
  }
  return deny("permission-denied", "role_not_allowed", "This role cannot send notifications.");
}

/** Roles the screen may target, with the spellings stored in users.role. */
const TARGET_ROLE_SPELLINGS: Record<string, string[]> = {
  delegate: ["delegate"],
  supervisor: ["supervisor", "company_supervisor"],
  admin: ["admin", "company-admin", "company_admin", "companyadmin"],
  marketing: ["marketing"],
  marketing_promotion: ["marketing_promotion", "marketingPromotion", "marketingpromotion"],
  organizationAdmin: ["organizationAdmin", "organization-admin", "organization_admin", "organizationadmin"],
  hr: ["hr", "company-hr", "company_hr", "human_resources"],
  accountant: ["accountant", "accounting", "account_admin"],
  branchesMarketingManager: [
    "branchesMarketingManager", "branches_marketing", "branches-marketing",
    "branches_marketing_manager", "branches-marketing-manager", "branchesmarketingmanager",
  ],
};

export function targetRoleSpellings(role: string): string[] | null {
  return TARGET_ROLE_SPELLINGS[role] ?? null;
}

export type ParsedRequest = {
  ok: true;
  title: string;
  body: string;
  type: string;
  target: NotifyTarget;
};

/** Validates the payload shape only. Scope is checked by authorizeTarget. */
export function parseRequest(data: unknown): ParsedRequest | Denial {
  const p = data && typeof data === "object" ? data as Record<string, unknown> : {};
  const title = str(p.title);
  const body = str(p.body);
  if (!title || !body) return deny("invalid-argument", "missing_text", "Title and body are required.");
  if (title.length > MAX_TITLE_LENGTH || body.length > MAX_BODY_LENGTH) {
    return deny("invalid-argument", "text_too_long", "Title or body is too long.");
  }
  const typeRaw = str(p.type) || "update";
  if (!(NOTIFICATION_TYPES as readonly string[]).includes(typeRaw)) {
    return deny("invalid-argument", "bad_type", "Unknown notification type.");
  }
  const t = p.target && typeof p.target === "object" ? p.target as Record<string, unknown> : {};
  const kind = str(t.kind);
  let target: NotifyTarget;
  switch (kind) {
  case "all":
    target = {kind: "all"};
    break;
  case "org":
    target = {kind: "org", org: str(t.organizationUID)};
    break;
  case "company":
    target = {kind: "company", org: str(t.organizationUID), company: str(t.companyUID)};
    if (!target.company) return deny("invalid-argument", "missing_company", "Company is required.");
    break;
  case "role": {
    const role = str(t.role);
    if (!targetRoleSpellings(role)) return deny("invalid-argument", "bad_role", "Unknown role.");
    target = {kind: "role", role};
    break;
  }
  case "user": {
    const uid = str(t.uid);
    const phoneRaw = str(t.phone);
    if (!uid && !phoneRaw) return deny("invalid-argument", "missing_user", "Phone or user is required.");
    let phone = "";
    if (phoneRaw) {
      phone = normalizePhone(phoneRaw);
      if (!/^\+?\d{8,15}$/.test(phone)) return deny("invalid-argument", "invalid_phone", "Phone is invalid.");
    }
    target = {kind: "user", phone, uid};
    break;
  }
  default:
    return deny("invalid-argument", "bad_target", "Unknown target.");
  }
  return {ok: true, title, body, type: typeRaw, target};
}

/**
 * Resolves the target against the caller scope. Org and company IDs are
 * filled from the scope when the caller did not send them; a different one is
 * rejected.
 */
export function authorizeTarget(
  scope: CallerScope,
  target: NotifyTarget,
): {ok: true; target: NotifyTarget} | Denial {
  if (scope.kind === "global") {
    if (target.kind === "org" && !target.org) {
      return deny("invalid-argument", "missing_org", "Organization is required.");
    }
    if (target.kind === "company" && !target.org) {
      return deny("invalid-argument", "missing_org", "Organization is required.");
    }
    return {ok: true, target};
  }
  const outOfScope = deny("permission-denied", "out_of_scope", "Target is outside your scope.");
  switch (target.kind) {
  case "all":
    return deny("permission-denied", "broadcast_global_only", "Only global staff can send to everyone.");
  case "org": {
    if (scope.kind !== "org") return outOfScope;
    const org = target.org || scope.org;
    return org === scope.org ? {ok: true, target: {kind: "org", org}} : outOfScope;
  }
  case "company": {
    const org = target.org || scope.org;
    if (org !== scope.org) return outOfScope;
    if (scope.kind === "company" && target.company !== scope.company) return outOfScope;
    return {ok: true, target: {kind: "company", org, company: target.company}};
  }
  case "role":
  case "user":
    return {ok: true, target};
  }
  return outOfScope;
}

/** A recipient candidate as read from users/ or a nested delegates/ doc. */
export type Candidate = {
  uid: string;
  orgIds: string[];
  companyIds: string[];
  phone: string;
  name: string;
  role: string;
  data: Record<string, unknown>;
};

function stringList(v: unknown): string[] {
  return Array.isArray(v) ? v.map(str).filter(Boolean) : [];
}

/**
 * Builds a candidate. `path` is the doc path; for
 * organizations/{org}/companies/{co}/delegates/{id} the org and company come
 * from the path too, so docs without those fields still scope correctly.
 */
export function candidateFrom(
  id: string,
  path: string,
  data: Record<string, unknown>,
): Candidate | null {
  const uid = str(data.uid) || id;
  if (!uid) return null;
  const orgIds = new Set<string>([
    str(data.organizationUID), str(data.organizationId), ...stringList(data.organizationUIDs),
  ]);
  const companyIds = new Set<string>([
    str(data.companyUID), str(data.companyId), ...stringList(data.companyIds),
  ]);
  const parts = path.split("/");
  if (parts.length >= 6 && parts[0] === "organizations" && parts[2] === "companies") {
    orgIds.add(parts[1]);
    companyIds.add(parts[3]);
  }
  orgIds.delete("");
  companyIds.delete("");
  return {
    uid,
    orgIds: Array.from(orgIds),
    companyIds: Array.from(companyIds),
    phone: str(data.phoneNumber) || str(data.phone),
    name: str(data.fullName) || str(data.displayName) || str(data.name),
    role: str(data.role),
    data,
  };
}

/** Second layer: every recipient must match the caller scope. */
export function candidateInScope(scope: CallerScope, c: Candidate): boolean {
  if (scope.kind === "global") return true;
  if (scope.kind === "org") return c.orgIds.includes(scope.org);
  return c.companyIds.includes(scope.company);
}

/** Skips deleted, suspended, inactive and privileged staff the caller may not reach. */
export function candidateEligible(scope: CallerScope, c: Candidate): boolean {
  const status = str(c.data.status).toLowerCase();
  if (status === "suspended" || status === "deleted" || status === "inactive") return false;
  if (c.data.isActive === false || c.data.deleted === true || c.data.isDeleted === true) return false;
  if (scope.kind !== "global" && GLOBAL_ROLES.has(roleKey(c.role))) return false;
  return true;
}

/** Dedupes by uid and keeps only in-scope, eligible recipients. */
export function filterRecipients(scope: CallerScope, candidates: Candidate[]): Candidate[] {
  const seen = new Map<string, Candidate>();
  for (const c of candidates) {
    if (seen.has(c.uid)) continue;
    if (!candidateInScope(scope, c) || !candidateEligible(scope, c)) continue;
    seen.set(c.uid, c);
  }
  return Array.from(seen.values());
}

/** Phone variants for `in` queries, same normalisation as staffPhoneLookup. */
export function phoneVariants(phone: string): string[] {
  return phoneQueryVariants(normalizePhone(phone));
}

/** The org/company a recipient doc is filed under, inside the caller scope. */
export function recipientOrgCompany(
  scope: CallerScope,
  c: Candidate,
): {organizationId: string; companyId: string} {
  if (scope.kind === "company") return {organizationId: scope.org, companyId: scope.company};
  if (scope.kind === "org") {
    return {organizationId: scope.org, companyId: c.companyIds[0] ?? ""};
  }
  return {organizationId: c.orgIds[0] ?? "", companyId: c.companyIds[0] ?? ""};
}

/** Dart UserRole enum name, which the client wrote as senderRole. */
export function senderRoleName(role: unknown): string {
  const k = roleKey(role);
  if (k === "super_admin" || k === "superadmin") return "superAdmin";
  if (GLOBAL_ROLES.has(k)) return "technicalSupport";
  if (ORG_ROLES.has(k)) return "organizationAdmin";
  if (k === "marketing") return "marketing";
  if (MARKETING_ROLES.has(k)) return "marketingPromotion";
  if (["hr", "company_hr", "human_resources"].includes(k)) return "hr";
  if (["accountant", "accounting", "account_admin"].includes(k)) return "accountant";
  if (k.startsWith("branches")) return "branchesMarketingManager";
  if (COMPANY_ROLES.has(k)) return "admin";
  return k || "admin";
}

export const ROLE_LABELS_AR: Record<string, string> = {
  delegate: "المناديب",
  supervisor: "المشرفين",
  marketing: "مسؤولي تسويق الفروع",
  marketing_promotion: "مسؤولي العروض الترويجية",
  admin: "مشرفي الشركات",
  organizationAdmin: "مدراء المنظمات",
  hr: "الموارد البشرية",
  accountant: "المحاسبين",
  branchesMarketingManager: "مديري تسويق الفروع",
};

export type NotificationFields = {
  title: string;
  body: string;
  type: string;
  senderUid: string;
  senderName: string;
  senderRole: string;
  broadcastId: string;
};

/**
 * The notifications doc the inbox and onNotificationCreated read. The caller
 * adds createdAt (server timestamp).
 */
export function notificationDoc(
  f: NotificationFields,
  delegateUid: string,
  organizationId: string,
  companyId: string,
  phoneNumber?: string,
): Record<string, unknown> {
  const doc: Record<string, unknown> = {
    delegateUid,
    organizationId,
    companyId,
    title: f.title,
    body: f.body,
    type: f.type,
    isRead: false,
    deletedBy: [],
    senderName: f.senderName,
    senderRole: f.senderRole,
    senderUid: f.senderUid,
    createdBy: f.senderUid,
    broadcastId: f.broadcastId,
  };
  if (phoneNumber) doc.phoneNumber = phoneNumber;
  return doc;
}

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
