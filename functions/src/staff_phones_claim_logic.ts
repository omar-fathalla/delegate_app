/**
 * Pure helpers for minting staff JWT `phones` custom claims (TA-60 bell parity).
 * Variants align with delegate_login_logic phoneQueryVariants / normalizePhone.
 */
import {normalizePhone, phoneQueryVariants} from "./delegate_login_logic";
import {isStaffRole} from "./staff_phone_lookup_logic";

export const STAFF_PHONES_CLAIM_KEY = "phones";

export function staffPhonesFromStoredPhone(raw: unknown): string[] {
  if (typeof raw !== "string" || !raw.trim()) return [];
  const normalized = normalizePhone(raw);
  if (!normalized) return [];
  return phoneQueryVariants(normalized);
}

export interface StaffPhonesMintDecision {
  action: "set" | "clear" | "skip";
  phones?: string[];
  reason?: string;
}

/**
 * Merge `phones` into existing custom claims without wiping delegate/staff fields.
 */
export function mergeStaffPhonesClaims(
  existing: Record<string, unknown> | undefined,
  decision: StaffPhonesMintDecision,
): Record<string, unknown> {
  const next = {...(existing || {})};
  if (decision.action === "set" && decision.phones && decision.phones.length > 0) {
    next[STAFF_PHONES_CLAIM_KEY] = decision.phones;
    return next;
  }
  delete next[STAFF_PHONES_CLAIM_KEY];
  return next;
}

export function phoneFieldChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): boolean {
  const b = typeof before?.phoneNumber === "string" ? before.phoneNumber.trim() : "";
  const a = typeof after?.phoneNumber === "string" ? after.phoneNumber.trim() : "";
  return b !== a;
}

export function shouldProcessStaffUser(data: Record<string, unknown> | undefined): boolean {
  if (!data) return false;
  return isStaffRole(data.role);
}

/** Collision when another users doc or delegate holds any variant of this phone. */
export function phoneOwnedByOther(
  ownerUid: string,
  hits: {collection: "users" | "delegate"; id: string}[],
): boolean {
  return hits.some((h) => h.id !== ownerUid);
}

export function decideStaffPhonesMint(
  phoneRaw: unknown,
  collision: boolean,
  trustedAdminWrite?: boolean,
): StaffPhonesMintDecision {
  const phones = staffPhonesFromStoredPhone(phoneRaw);
  if (phones.length === 0) {
    return {action: "clear", reason: "empty_phone"};
  }
  if (collision && !trustedAdminWrite) {
    return {action: "skip", reason: "phone_collision"};
  }
  if (collision && trustedAdminWrite) {
    return {action: "skip", reason: "phone_collision_admin_blocked"};
  }
  return {action: "set", phones};
}