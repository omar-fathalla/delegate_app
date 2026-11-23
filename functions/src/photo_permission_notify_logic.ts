/**
 * Recipients for a new pending photo-permission request.
 * Company admin / supervisor of the delegate's company (one role),
 * org-admins of the delegate's organization, marketing-promotion of
 * the same company (or of the organization when it has no company), and
 * global approvers (super-admin, technical support).
 */
const COMPANY_ADMIN_ROLES = new Set([
  "admin",
  "supervisor",
  "company-admin",
  "company_admin",
  "companyadmin",
  "company_supervisor",
  "company-supervisor",
]);

const ORG_ADMIN_ROLES = new Set([
  "organization-admin",
  "organization_admin",
  "organizationadmin",
  "organizationAdmin",
]);

const MARKETING_PROMOTION_ROLES = new Set([
  "marketingPromotion",
  "marketing_promotion",
  "marketing-promotion",
  "marketingpromotion",
]);

const GLOBAL_APPROVER_ROLES = new Set([
  "super-admin",
  "super_admin",
  "superadmin",
  "superAdmin",
  "Super-Admin",
  "SUPER_ADMIN",
  "technical_support",
  "technical-support",
  "technicalSupport",
  "technicalsupport",
  "tech_support",
  "techsupport",
]);

export function canonicalizeNotifyRole(role: unknown): string {
  return String(role || "").trim().toLowerCase().replace(/_/g, "-");
}

export function isCompanyAdminNotifyRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  const canon = canonicalizeNotifyRole(role);
  return COMPANY_ADMIN_ROLES.has(raw) || COMPANY_ADMIN_ROLES.has(canon);
}

export function isOrgAdminNotifyRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  const canon = canonicalizeNotifyRole(role);
  return ORG_ADMIN_ROLES.has(raw) || ORG_ADMIN_ROLES.has(canon);
}

export function isMarketingPromotionNotifyRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  const canon = canonicalizeNotifyRole(role);
  return MARKETING_PROMOTION_ROLES.has(raw) || MARKETING_PROMOTION_ROLES.has(canon);
}

export function isGlobalApproverNotifyRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  const canon = canonicalizeNotifyRole(role);
  return GLOBAL_APPROVER_ROLES.has(raw) || GLOBAL_APPROVER_ROLES.has(canon);
}

function orgIdsOf(u: {organizationUID?: unknown; organizationUIDs?: unknown}): string[] {
  const ids: string[] = [];
  const primary = String(u.organizationUID || "").trim();
  if (primary) ids.push(primary);
  const extra = u.organizationUIDs;
  if (Array.isArray(extra)) {
    for (const v of extra) {
      const s = String(v || "").trim();
      if (s) ids.push(s);
    }
  }
  return ids;
}

export function shouldNotifyPhotoPermissionUser(
  u: {
    id?: string;
    role?: unknown;
    companyUID?: unknown;
    organizationUID?: unknown;
    organizationUIDs?: unknown;
  },
  opts: {companyId: string; organizationId: string},
): boolean {
  const co = String(opts.companyId || "").trim();
  const org = String(opts.organizationId || "").trim();
  if (!u || !u.id) return false;
  if (isGlobalApproverNotifyRole(u.role)) return true;
  if (isMarketingPromotionNotifyRole(u.role)) {
    // TAS-270 #8: marketing promotion approves photo requests. With a
    // companyUID it follows that company; with none (org-wide, e.g.
    // Fathalla Market's promotion team) every request of its organization.
    const ownCo = String(u.companyUID || "").trim();
    if (ownCo !== "") return co !== "" && ownCo === co;
    return org !== "" && orgIdsOf(u).includes(org);
  }
  if (isCompanyAdminNotifyRole(u.role)) {
    return co !== "" && String(u.companyUID || "").trim() === co;
  }
  if (isOrgAdminNotifyRole(u.role)) {
    return org !== "" && orgIdsOf(u).includes(org);
  }
  return false;
}

export function photoPermissionNotifyUserIds(
  users: {
    id: string;
    role?: unknown;
    companyUID?: unknown;
    organizationUID?: unknown;
    organizationUIDs?: unknown;
  }[],
  companyId: string,
  organizationId = "",
): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const u of users) {
    if (!shouldNotifyPhotoPermissionUser(u, {companyId, organizationId})) continue;
    if (seen.has(u.id)) continue;
    seen.add(u.id);
    out.push(u.id);
  }
  return out;
}
