/**
 * Pure helpers for the delegate phone change (TAS-112).
 *
 * User decision 2026-11-24: a delegate changes only its phone number, with
 * an OTP on the new number. The national ID stays with company admins /
 * supervisors and the super-admin (editDelegateProfile).
 *
 * Flow: requestDelegatePhoneChange({newPhone, nationalId}) records a pending
 * change; the app verifies the new number with Firebase Phone Auth and links
 * it to the delegate's Auth user; confirmDelegatePhoneChange() checks the
 * Auth phone is the requested one, then updates every copy at once.
 */
import {
  isEgyptianMobile,
  isUaeMobile,
  nationalIdsMatch,
  normalizePhone,
  phoneQueryVariants,
  phoneToE164,
} from "./delegate_login_logic";

export const PHONE_CHANGE_TTL_MS = 15 * 60 * 1000;
export const PHONE_CHANGE_MAX_PER_DAY = 5;
export const PHONE_CHANGE_COLLECTION = "delegate_phone_changes";

export type DenialCode =
  | "unauthenticated" | "permission-denied" | "invalid-argument"
  | "already-exists" | "failed-precondition" | "resource-exhausted" | "not-found";

export interface Denial {
  code: DenialCode;
  reason: string;
  message: string;
}

export function isDenial(v: unknown): v is Denial {
  return typeof v === "object" && v !== null && "reason" in v && "code" in v;
}

function deny(code: DenialCode, reason: string, message: string): Denial {
  return {code, reason, message};
}

/** 01xxxxxxxxx -> +201xxxxxxxxx, 05xxxxxxxx -> +9715xxxxxxxx (TAS-112). */
export function toE164(local: string): string {
  return phoneToE164(local);
}

export function isDelegateToken(token: Record<string, unknown> | undefined): boolean {
  return !!token && token.role === "delegate";
}

export interface ParsedRequest {
  newPhone: string; // 01xxxxxxxxx
  nationalId: string;
}

export function parseRequest(data: unknown): ParsedRequest | Denial {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const rawPhone = typeof d.newPhone === "string" ? d.newPhone : "";
  const rawId = typeof d.nationalId === "string" ? d.nationalId : "";
  const phone = normalizePhone(rawPhone);
  // User decision 2026-11-24: Egyptian or UAE mobiles.
  if (!isEgyptianMobile(phone) && !isUaeMobile(phone)) {
    return deny("invalid-argument", "bad_phone", "Enter a valid Egyptian or UAE mobile number.");
  }
  if (!rawId.trim()) {
    return deny("invalid-argument", "bad_national_id", "Enter your national ID.");
  }
  return {newPhone: phone, nationalId: rawId};
}

export interface OwnDelegateDoc {
  path: string;
  id: string;
  phone: string;
  nationalId: string;
}

/**
 * The caller's own delegate copies: ids from the token (uid, delegateIds)
 * among the docs found by the token's phones.
 */
export function ownDocs(
  uid: string,
  token: Record<string, unknown>,
  found: OwnDelegateDoc[],
): OwnDelegateDoc[] {
  const ids = new Set<string>([uid]);
  if (Array.isArray(token.delegateIds)) {
    for (const v of token.delegateIds) if (typeof v === "string") ids.add(v);
  }
  if (typeof token.delegateId === "string") ids.add(token.delegateId);
  const seen = new Set<string>();
  return found.filter((d) => ids.has(d.id) && !seen.has(d.path) && !!seen.add(d.path));
}

export function decideRequest(input: {
  parsed: ParsedRequest;
  own: OwnDelegateDoc[];
  otherDelegateWithPhone: boolean;
  staffWithPhone: boolean;
  requestsToday: number;
}): {ok: true} | Denial {
  const {parsed, own} = input;
  if (own.length === 0) {
    return deny("failed-precondition", "no_profile", "Your delegate profile was not found.");
  }
  if (!own.some((d) => nationalIdsMatch(d.nationalId, parsed.nationalId))) {
    return deny("permission-denied", "national_id_mismatch", "The national ID does not match your profile.");
  }
  const current = new Set(own.map((d) => normalizePhone(d.phone)));
  if (current.has(parsed.newPhone)) {
    return deny("invalid-argument", "same_phone", "This is already your number.");
  }
  if (input.otherDelegateWithPhone || input.staffWithPhone) {
    return deny("already-exists", "phone_taken", "This number belongs to another account.");
  }
  if (input.requestsToday >= PHONE_CHANGE_MAX_PER_DAY) {
    return deny("resource-exhausted", "too_many", "Too many attempts today. Try again tomorrow.");
  }
  return {ok: true};
}

export interface PendingChange {
  newPhone: string;
  status: string;
  expiresAtMs: number;
}

export function decideConfirm(input: {
  pending: PendingChange | null;
  authPhoneE164: string | undefined;
  nowMs: number;
  otherDelegateWithPhone: boolean;
  staffWithPhone: boolean;
}): {ok: true; newPhone: string} | Denial {
  const p = input.pending;
  if (!p || p.status !== "pending") {
    return deny("not-found", "no_request", "Start the phone change again.");
  }
  if (input.nowMs > p.expiresAtMs) {
    return deny("failed-precondition", "expired", "The request expired. Start again.");
  }
  const auth = input.authPhoneE164 ? normalizePhone(input.authPhoneE164) : "";
  if (!auth || auth !== p.newPhone) {
    return deny("failed-precondition", "phone_not_verified", "Verify the new number with the code first.");
  }
  if (input.otherDelegateWithPhone || input.staffWithPhone) {
    return deny("already-exists", "phone_taken", "This number belongs to another account.");
  }
  return {ok: true, newPhone: p.newPhone};
}

/** Claims after the change: phones follow the new number, the rest stays. */
export function nextClaims(claims: Record<string, unknown>, newPhone: string): Record<string, unknown> {
  const next: Record<string, unknown> = {...claims, phones: phoneQueryVariants(newPhone)};
  if (next.otp_required === true) next.otp_verified = true;
  return next;
}

/** Patch for one delegate copy: write the phone fields that copy uses. */
export function delegatePatch(data: Record<string, unknown>, newPhone: string): Record<string, unknown> {
  const patch: Record<string, unknown> = {phoneNumber: newPhone};
  if (typeof data.phone === "string" && data.phone.trim()) patch.phone = newPhone;
  return patch;
}

/** 0100****001 for logs and the audit doc. */
export function maskPhone(phone: string): string {
  const p = normalizePhone(phone);
  return p.length >= 7 ? `${p.slice(0, 4)}****${p.slice(-3)}` : "***";
}

export function dayKey(nowMs: number): string {
  return new Date(nowMs + 2 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
