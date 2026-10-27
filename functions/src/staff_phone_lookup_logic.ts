/**
 * Pure helpers for staffPhoneLookup.
 *
 * The callable returns only the fields the login screen needs. It does not
 * return a password, a national ID, or documents whose role is not staff.
 */

const STAFF_WEIGHTS: Record<string, number> = {
  super_admin: 100,
  superadmin: 100,
  technical_support: 90,
  technicalsupport: 90,
  tech_support: 90,
  techsupport: 90,
  accountant: 85,
  accounting: 85,
  account_admin: 85,
  organization_admin: 80,
  organizationadmin: 80,
  hr: 75,
  company_hr: 75,
  human_resources: 75,
  company_admin: 70,
  companyadmin: 70,
  admin: 70,
  branches_marketing: 65,
  branches_marketing_manager: 65,
  branchesmarketingmanager: 65,
  supervisor: 60,
  company_supervisor: 60,
  marketing: 50,
  marketing_promotion: 50,
  marketingpromotion: 50,
};

export function normalizeRoleKey(role: unknown): string {
  return typeof role === "string" ? role.trim().toLowerCase().replace(/-/g, "_") : "";
}

export function staffRoleWeight(role: unknown): number {
  return STAFF_WEIGHTS[normalizeRoleKey(role)] ?? 0;
}

export function isStaffRole(role: unknown): boolean {
  return staffRoleWeight(role) > 0;
}

export interface PublicStaffProfile {
  uid: string;
  email: string;
  role: string;
  displayName: string;
  phoneNumber: string;
  organizationUID: string;
  organizationName: string;
  companyUID: string;
  companyName: string;
}

function text(data: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

/**
 * Fields the client may see before password sign-in. Null when the document
 * is not a staff account or has no email for Firebase Auth.
 */
export function publicStaffProfile(
  id: string,
  data: Record<string, unknown>,
  normalizedPhone: string,
): PublicStaffProfile | null {
  if (!isStaffRole(data.role)) return null;
  const email = text(data, ["email"]);
  if (!email.includes("@")) return null;
  const displayName = text(data, ["displayName", "fullName", "name"]) || "Admin";
  return {
    uid: id,
    email,
    role: typeof data.role === "string" ? data.role : "",
    displayName,
    phoneNumber: normalizedPhone,
    organizationUID: text(data, ["organizationUID", "organizationId", "orgId"]),
    organizationName: text(data, ["organizationName", "organization_name"]),
    companyUID: text(data, ["companyUID", "companyId"]),
    companyName: text(data, ["companyName", "company_name"]),
  };
}

export function pickStaffProfile(
  profiles: PublicStaffProfile[],
): PublicStaffProfile | null {
  if (profiles.length === 0) return null;
  const ordered = profiles.slice().sort((a, b) => staffRoleWeight(b.role) - staffRoleWeight(a.role));
  return ordered[0];
}
