/**
 * Pure helpers for minting staff JWT `phones` custom claims (TA-60 bell parity).
 * Variants align with delegate_login_logic phoneQueryVariants / normalizePhone.
 */
import {normalizePhone, phoneQueryVariants} from "./delegate_login_logic";
import {isStaffRole} from "./staff_phone_lookup_logic";

export const STAFF_PHONES_CLAIM_KEY = "phones";

/**
 * Every field a phone identity can live in on users and delegate docs.
 * Superset of delegate_login_logic PHONE_FIELDS and the 1.14.3 bell reads.
 */
export const PHONE_OWNER_FIELDS = ["phoneNumber", "phone", "mobile", "mobileNumber"] as const;

export function normalizeStoredPhone(raw: unknown): string {
  if (typeof raw === "number" && Number.isFinite(raw)) return normalizePhone(String(raw));
  if (typeof raw !== "string" || !raw.trim()) return "";
  return normalizePhone(raw);
}

export function staffPhonesFromStoredPhone(raw: unknown): string[] {
  const normalized = normalizeStoredPhone(raw);
  if (!normalized) return [];
  return phoneQueryVariants(normalized);
}

/** True when any phone field on the doc normalizes to the same phone. */
export function docHoldsPhone(data: Record<string, unknown> | undefined, normalizedTarget: string): boolean {
  if (!data || !normalizedTarget) return false;
  return PHONE_OWNER_FIELDS.some((field) => normalizeStoredPhone(data[field]) === normalizedTarget);
}

/**
 * Exact values for indexed `in` lookups: string variants plus numeric forms
 * for docs that stored the phone as a number. At most 10 values.
 */
export function phoneCollisionQueryValues(normalizedTarget: string): (string | number)[] {
  const values: (string | number)[] = phoneQueryVariants(normalizedTarget);
  if (/^0\d{10}$/.test(normalizedTarget)) {
    values.push(Number(normalizedTarget.substring(1)));
    values.push(Number("20" + normalizedTarget.substring(1)));
  }
  return values;
}

export interface StaffPhonesMintDecision {
  action: "set" | "clear";
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

/** Collision when another users doc or delegate holds this phone. */
export function phoneOwnedByOther(
  ownerUid: string,
  hits: {collection: "users" | "delegate"; id: string}[],
): boolean {
  return hits.some((h) => h.id !== ownerUid);
}

/**
 * Auth `phoneNumber` is set only by the Admin SDK or a verified phone sign-in,
 * so it wins over the client-writable users doc field when present.
 */
export function resolveStaffMintPhone(
  authPhone: unknown,
  docPhone: unknown,
): {source: "auth" | "users_doc" | "none"; phone: string} {
  if (typeof authPhone === "string" && authPhone.trim()) return {source: "auth", phone: authPhone.trim()};
  if (typeof docPhone === "string" && docPhone.trim()) return {source: "users_doc", phone: docPhone.trim()};
  return {source: "none", phone: ""};
}

/**
 * A collision clears any existing claim: an old claim must not outlive the
 * phone it was minted from.
 */
export function decideStaffPhonesMint(phoneRaw: unknown, collision: boolean): StaffPhonesMintDecision {
  const phones = staffPhonesFromStoredPhone(phoneRaw);
  if (phones.length === 0) {
    return {action: "clear", reason: "empty_phone"};
  }
  if (collision) {
    return {action: "clear", reason: "phone_collision"};
  }
  return {action: "set", phones};
}
