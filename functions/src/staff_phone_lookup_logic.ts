/**
 * Pure helpers for staffPhoneLookup.
 *
 * TAS-314: a signed-out caller gets the email only (Firebase Auth needs it
 * for signInWithEmailAndPassword). The role, names and org/company fields go
 * back only to the signed-in owner of the account. Nothing here returns a
 * password, a national ID, or documents whose role is not staff.
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
  supervisor: 70,
  company_supervisor: 70,
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

/** What a signed-out (or anonymous, or other) caller receives. */
export interface MinimalStaffLookup {
  email: string;
}

export interface LookupCaller {
  uid: string;
  email: string;
  anonymous: boolean;
}

/** Caller identity from the callable context; null when signed out. */
export function lookupCallerOf(auth: unknown): LookupCaller | null {
  if (!auth || typeof auth !== "object") return null;
  const a = auth as {uid?: unknown; token?: Record<string, unknown>};
  const uid = typeof a.uid === "string" ? a.uid : "";
  if (!uid) return null;
  const token = a.token && typeof a.token === "object" ? a.token : {};
  const firebase = token.firebase && typeof token.firebase === "object" ?
    token.firebase as Record<string, unknown> : {};
  return {
    uid,
    email: typeof token.email === "string" ? token.email : "",
    anonymous: firebase.sign_in_provider === "anonymous",
  };
}

/** True when the signed-in caller is the account the phone belongs to. */
export function callerOwnsProfile(profile: PublicStaffProfile, caller: LookupCaller | null): boolean {
  if (!caller || caller.anonymous) return false;
  if (caller.uid === profile.uid) return true;
  const a = caller.email.trim().toLowerCase();
  return a !== "" && a === profile.email.trim().toLowerCase();
}

/**
 * TAS-314: the response body. The owner (after password sign-in) gets the
 * full profile; everyone else gets the email only.
 */
export function staffLookupResponse(
  profile: PublicStaffProfile,
  caller: LookupCaller | null,
): PublicStaffProfile | MinimalStaffLookup {
  if (callerOwnsProfile(profile, caller)) return profile;
  return {email: profile.email};
}

export function pickStaffProfile(
  profiles: PublicStaffProfile[],
): PublicStaffProfile | null {
  if (profiles.length === 0) return null;
  const ordered = profiles.slice().sort((a, b) => staffRoleWeight(b.role) - staffRoleWeight(a.role));
  return ordered[0];
}

/**
 * TAS-24: per-caller (IP) window on top of the per-phone lock, so the
 * callable cannot be used to walk many numbers. Every lookup counts.
 */
export const IP_WINDOW_MS = 15 * 60 * 1000;
export const IP_MAX_LOOKUPS = 20;

export interface IpWindowState {
  count: number;
  windowStartMs: number;
}

export function ipWindowNext(
  state: IpWindowState | null,
  now: number,
  windowMs = IP_WINDOW_MS,
  max = IP_MAX_LOOKUPS,
): IpWindowState & {allowed: boolean; retryAfterSeconds: number} {
  const fresh = !state || now - state.windowStartMs >= windowMs || now < state.windowStartMs;
  const windowStartMs = fresh ? now : (state as IpWindowState).windowStartMs;
  const count = (fresh ? 0 : (state as IpWindowState).count) + 1;
  const allowed = count <= max;
  const retryAfterSeconds = allowed ? 0 : Math.max(1, Math.ceil((windowStartMs + windowMs - now) / 1000));
  return {count, windowStartMs, allowed, retryAfterSeconds};
}

/** Best-effort caller IP from the callable request (first X-Forwarded-For hop). */
export function callerIp(headers: Record<string, unknown> | undefined, ip: unknown): string {
  const fwd = headers ? headers["x-forwarded-for"] : undefined;
  const first = typeof fwd === "string" ? fwd.split(",")[0].trim() : "";
  if (first) return first;
  return typeof ip === "string" ? ip : "";
}
