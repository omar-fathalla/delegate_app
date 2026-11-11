/**
 * Recipients for a new pending photo-permission request.
 * Only company admin / supervisor of the delegate's company
 * (roles treated as one). Org-admin of other companies in the
 * same org are not notified.
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

export function canonicalizeNotifyRole(role: unknown): string {
  return String(role || "").trim().toLowerCase().replace(/_/g, "-");
}

export function isCompanyAdminNotifyRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  const canon = canonicalizeNotifyRole(role);
  return COMPANY_ADMIN_ROLES.has(raw) || COMPANY_ADMIN_ROLES.has(canon);
}

export function photoPermissionNotifyUserIds(
  users: {id: string; role?: unknown; companyUID?: unknown}[],
  companyId: string,
): string[] {
  const co = String(companyId || "").trim();
  if (!co) return [];
  const out: string[] = [];
  for (const u of users) {
    if (!isCompanyAdminNotifyRole(u.role)) continue;
    if (String(u.companyUID || "").trim() !== co) continue;
    out.push(u.id);
  }
  return out;
}
