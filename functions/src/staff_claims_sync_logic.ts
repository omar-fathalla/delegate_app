/**
 * TAS-23: pure rules for the staff role claims (role, orgId, organizationId,
 * companyId). Shared by:
 *   - createStaffUser (staffClaimsFor in staff_claims.ts),
 *   - the users/{uid} sync trigger (staff_claims_sync.ts),
 *   - the one-off backfill (functions/scripts/backfill_staff_claims.js).
 *
 * Trust model (see staff_claims_sync.ts for the trigger side):
 *   - Claims are written with the Admin SDK only.
 *   - users/{uid}.role is NOT proof on its own: it was client-writable under
 *     older rules, and staff in scope can still write it. A claim is granted
 *     or changed only when a server-side record confirms the same role and
 *     scope: organizations/{org}/members/{uid} or
 *     organizations/{org}/companies/{co}/members/{uid} (written by
 *     claimInvite / createAdminUser / approvals, or by the super admin and
 *     the chain's own org admin under the rules).
 *   - Global roles (super-admin, technical_support, accountant) are never
 *     granted from a users doc: only createStaffUser / createAdminUser or an
 *     operator allow-list in the backfill.
 *   - Removing or narrowing a staff claim is always safe (fail closed).
 */

/** Canonical claim spelling per staff role (letters-only key, like the rules' normRoleStr). */
const CANON: Record<string, string> = {
  superadmin: "super-admin",
  technicalsupport: "technical_support",
  techsupport: "technical_support",
  accountant: "accountant",
  accounting: "accountant",
  accountadmin: "accountant",
  organizationadmin: "organization-admin",
  orgadmin: "organization-admin",
  companyadmin: "company-admin",
  admin: "company-admin",
  supervisor: "supervisor",
  companysupervisor: "supervisor",
  hr: "hr",
  companyhr: "hr",
  humanresources: "hr",
  marketing: "marketing",
  marketingpromotion: "marketing_promotion",
  branchesmarketing: "branches_marketing",
  branchesmarketingmanager: "branches_marketing",
};

export type Scope = "global" | "org" | "company" | "org-or-company";

const SCOPE: Record<string, Scope> = {
  "super-admin": "global",
  "technical_support": "global",
  "accountant": "global",
  "organization-admin": "org",
  "company-admin": "company",
  "supervisor": "company",
  "hr": "company",
  "marketing": "org-or-company",
  "marketing_promotion": "org-or-company",
  "branches_marketing": "org-or-company",
};

/** Roles whose claims the sync trigger never touches (managed by the admin web flows). */
export const TRIGGER_UNTOUCHED = new Set(["super-admin", "technical_support"]);

export const STAFF_CLAIM_KEYS = ["role", "orgId", "organizationId", "companyId"] as const;

export type Data = Record<string, unknown> | null | undefined;

export interface StaffClaims {
  role: string;
  orgId: string;
  organizationId: string;
  companyId: string;
}

export function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Canonical staff role, or "" for delegates, promoters, empty and unknown roles. */
export function canonicalStaffRole(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return CANON[raw.toLowerCase().replace(/[^a-z]/g, "")] || "";
}

export function roleScope(canon: string): Scope | null {
  return SCOPE[canon] || null;
}

/**
 * The claims a role + scope maps to, or null with a reason when the scope a
 * role needs is missing. Global roles carry no org/company.
 */
export function claimsForRole(
  rawRole: unknown,
  org: unknown,
  co: unknown,
): {claims: StaffClaims | null; reason: string} {
  const role = canonicalStaffRole(rawRole);
  if (!role) return {claims: null, reason: "not a staff role"};
  const scope = roleScope(role) as Scope;
  if (scope === "global") return {claims: {role, orgId: "", organizationId: "", companyId: ""}, reason: ""};
  const o = str(org);
  if (!o) return {claims: null, reason: "no organization on users doc"};
  if (scope === "org") return {claims: {role, orgId: o, organizationId: o, companyId: ""}, reason: ""};
  const c = str(co);
  if (scope === "company" && !c) return {claims: null, reason: "no company on users doc"};
  return {claims: {role, orgId: o, organizationId: o, companyId: c}, reason: ""};
}

/** The claims a users doc asks for (role + organizationUID/Id + companyUID/Id). */
export function desiredFromDoc(doc: Data): {claims: StaffClaims | null; reason: string} {
  if (!doc) return {claims: null, reason: "users doc deleted"};
  return claimsForRole(doc.role, str(doc.organizationUID) || str(doc.organizationId), str(doc.companyUID) || str(doc.companyId));
}

/** The staff part of the current claims, normalised (null when the token has no staff role). */
export function currentStaffClaims(claims: Data): StaffClaims | null {
  const c = claims || {};
  const role = canonicalStaffRole(c.role);
  if (!role) return null;
  const org = str(c.orgId) || str(c.organizationId);
  return {role, orgId: org, organizationId: org, companyId: str(c.companyId)};
}

export function sameStaffClaims(a: StaffClaims | null, b: StaffClaims | null): boolean {
  if (!a || !b) return a === b;
  return a.role === b.role && a.orgId === b.orgId && a.companyId === b.companyId;
}

/** True when the raw claims already hold exactly these keys (no rewrite needed). */
export function claimsWritten(claims: Data, want: StaffClaims): boolean {
  const c = claims || {};
  return c.role === want.role && str(c.orgId) === want.orgId && str(c.organizationId) === want.organizationId &&
    str(c.companyId) === want.companyId;
}

/** Existing claims with the staff keys replaced (other keys, e.g. mfaGraceUntil, kept). */
export function mergeStaffClaims(existing: Data, want: StaffClaims): Record<string, unknown> {
  return {...(existing || {}), ...want};
}

/** Existing claims without the staff keys. */
export function stripStaffClaims(existing: Data): Record<string, unknown> {
  const out: Record<string, unknown> = {...(existing || {})};
  for (const k of STAFF_CLAIM_KEYS) delete out[k];
  return out;
}

/** Server-side membership docs that may confirm these claims (any one is enough). */
export function membershipPaths(uid: string, want: StaffClaims): string[] {
  const scope = roleScope(want.role);
  const org = `organizations/${want.orgId}/members/${uid}`;
  const co = want.companyId ? `organizations/${want.orgId}/companies/${want.companyId}/members/${uid}` : "";
  if (scope === "org") return [org];
  if (scope === "company") return [co];
  if (scope === "org-or-company") return co ? [co, org] : [org];
  return [];
}

/**
 * A membership doc confirms the claims when it exists, is not inactive, and,
 * for an organization admin, says organization admin.
 */
export function membershipConfirms(member: Data, want: StaffClaims): boolean {
  if (!member) return false;
  const status = str(member.status).toLowerCase();
  if (status && status !== "active") return false;
  if (want.role === "organization-admin") return canonicalStaffRole(member.role) === "organization-admin";
  return true;
}

function scopeOf(doc: Data): string {
  if (!doc) return "\u0000deleted";
  return [canonicalStaffRole(doc.role) || `raw:${str(doc.role)}`,
    str(doc.organizationUID) || str(doc.organizationId),
    str(doc.companyUID) || str(doc.companyId)].join("|");
}

export type SyncPlan =
  | {action: "noop"; reason: string}
  | {action: "revoke"; reason: string}
  | {action: "grant"; want: StaffClaims; reason: string};

/**
 * What the sync trigger does for one users/{uid} write, before the
 * membership lookup. "grant" still needs membershipConfirms(); when it does
 * not confirm, the caller revokes if the token held a staff role, else noop.
 */
export function planStaffClaimSync(before: Data, after: Data, claims: Data): SyncPlan {
  if (scopeOf(before) === scopeOf(after)) return {action: "noop", reason: "role and scope unchanged"};
  const cur = currentStaffClaims(claims);
  const curRole = canonicalStaffRole((claims || {}).role) || str((claims || {}).role).toLowerCase();
  if (curRole === "delegate") return {action: "noop", reason: "delegate claims are never touched"};
  if (cur && TRIGGER_UNTOUCHED.has(cur.role)) return {action: "noop", reason: `${cur.role} claims are managed by the admin web`};
  const want = desiredFromDoc(after);
  if (want.claims && sameStaffClaims(cur, want.claims)) return {action: "noop", reason: "claims already match"};
  if (!want.claims || roleScope(want.claims.role) === "global") {
    if (!cur) return {action: "noop", reason: want.claims ? "global role is never granted from a users doc" : want.reason};
    return {action: "revoke", reason: want.claims ? "global role is never granted from a users doc" : want.reason};
  }
  return {action: "grant", want: want.claims, reason: "needs membership"};
}

export type BackfillAction = "ok" | "set" | "manual" | "skip";

export interface BackfillInput {
  doc: Data;
  claims: Data;
  authExists: boolean;
  authDisabled: boolean;
  /** Membership docs read at membershipPaths(), in the same order (null = missing). */
  members: Data[];
  /** uid listed in the operator allow-list file. */
  allowListed: boolean;
}

/** One users doc in the backfill: what to do and why. */
export function planBackfill(i: BackfillInput): {action: BackfillAction; want: StaffClaims | null; reason: string} {
  const d = desiredFromDoc(i.doc);
  if (!canonicalStaffRole((i.doc || {}).role)) return {action: "skip", want: null, reason: "not a staff role"};
  if (!i.authExists) return {action: "skip", want: null, reason: "no Auth user"};
  if (i.authDisabled) return {action: "skip", want: null, reason: "Auth user disabled"};
  if (!d.claims) return {action: "manual", want: null, reason: d.reason};
  const want = d.claims;
  const rawCur = canonicalStaffRole((i.claims || {}).role) || str((i.claims || {}).role).toLowerCase();
  if (rawCur === "delegate") return {action: "manual", want, reason: "account carries delegate claims"};
  const cur = currentStaffClaims(i.claims);
  if (sameStaffClaims(cur, want)) {
    return claimsWritten(i.claims, want) ?
      {action: "ok", want, reason: "claims already match"} :
      {action: "set", want, reason: "same role and scope, claim keys normalised"};
  }
  if (i.allowListed) return {action: "set", want, reason: "operator allow-list"};
  if (roleScope(want.role) === "global") return {action: "manual", want, reason: "global role: add the uid to --allow-file after checking by hand"};
  if (i.members.some((m) => membershipConfirms(m, want))) return {action: "set", want, reason: "membership confirmed"};
  if (cur && cur.role === want.role && cur.orgId === want.orgId && (!want.companyId || cur.companyId === want.companyId)) {
    return {action: "set", want, reason: "role claim already present"};
  }
  return {action: "manual", want, reason: "no server membership confirms this role/scope"};
}
