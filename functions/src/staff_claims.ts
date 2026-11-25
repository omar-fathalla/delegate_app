/**
 * TAS-23: staff callables take the caller's role and scope from ID-token
 * custom claims, not from users/{uid}.
 *
 * Claims are written only with the Admin SDK (createStaffUser, claimInvite,
 * the staff claims backfill script). The users doc can be written by staff in
 * scope under the rules, and was client-writable under older rules, so a role
 * or company on it is not proof.
 *
 * Claim shape (same as the web callables and the backfill script):
 *   {role, orgId, organizationId, companyId}
 * role spellings: super-admin, technical_support, accountant,
 * organization-admin, company-admin, supervisor, hr, ... (any spelling that
 * normalizeRoleKey maps to a staff role).
 */
import {isStaffRole, normalizeRoleKey} from "./staff_phone_lookup_logic";

const GLOBAL = new Set([
  "super_admin", "superadmin",
  "technical_support", "technicalsupport", "tech_support", "techsupport",
  "accountant", "accounting", "account_admin",
]);
const ORG_LEVEL = new Set(["organization_admin", "organizationadmin", "org_admin"]);

const SCOPE_KEYS = ["organizationUID", "organizationId", "organizationUIDs", "companyUID", "companyId"];

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export interface RoleClaims {
  role: string;
  orgId: string;
  organizationId: string;
  companyId: string;
}

/** The staff claims to set for a users-doc role and scope (createStaffUser). */
export function staffClaimsFor(role: string, organizationUID: string, companyUID: string): RoleClaims | null {
  const key = normalizeRoleKey(role);
  if (!isStaffRole(role)) return null;
  const global = GLOBAL.has(key);
  const org = global ? "" : str(organizationUID);
  const co = global || ORG_LEVEL.has(key) ? "" : str(companyUID);
  return {role: str(role), orgId: org, organizationId: org, companyId: co};
}

/**
 * Returns a copy of the caller's users doc where the role and every scope
 * field come from the token claims:
 * - token role is a staff role: role = claim; organizationUID/organizationId
 *   = orgId claim, companyUID/companyId = companyId claim, organizationUIDs =
 *   [orgId]. A missing scope claim becomes "" so scope checks fail closed.
 *   Global roles (super-admin, technical support, accountant) keep no scope.
 * - token has no staff role but the doc claims one: role becomes "" and the
 *   scope fields are cleared, so the doc alone never grants staff power.
 * - neither (delegates, promoters, empty): the doc is returned as is; those
 *   roles grant no staff power and keep the paths that already check them.
 * Other fields (isActive, names, phone) still come from the doc.
 */
export function claimBackedCaller(
  doc: Record<string, unknown> | null | undefined,
  token: unknown,
): Record<string, unknown> {
  const d: Record<string, unknown> = {...(doc || {})};
  const t = (token && typeof token === "object" ? token : {}) as Record<string, unknown>;
  const claimRole = str(t.role);
  if (isStaffRole(claimRole)) {
    const key = normalizeRoleKey(claimRole);
    const global = GLOBAL.has(key);
    const org = global ? "" : str(t.orgId) || str(t.organizationId);
    const co = global || ORG_LEVEL.has(key) ? "" : str(t.companyId);
    d.role = claimRole;
    d.organizationUID = org;
    d.organizationId = org;
    d.organizationUIDs = org ? [org] : [];
    d.companyUID = co;
    d.companyId = co;
    return d;
  }
  if (isStaffRole(d.role)) {
    d.role = "";
    for (const k of SCOPE_KEYS) delete d[k];
  }
  return d;
}

/** True when the users doc says staff but the token has no staff role claim. */
export function staffClaimMissing(doc: Record<string, unknown> | null | undefined, token: unknown): boolean {
  const t = (token && typeof token === "object" ? token : {}) as Record<string, unknown>;
  return isStaffRole((doc || {}).role) && !isStaffRole(t.role);
}
