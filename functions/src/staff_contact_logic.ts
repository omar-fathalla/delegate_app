/**
 * Pure helpers for updateOwnStaffContact (TAS-49).
 *
 * A staff member's phone and email in users/{uid} are no longer client
 * writable: rules read them (own-record lists, phone-matched
 * notifications), so a self-edit to someone else's number or email used to
 * hand over that person's data. The phone is set here after a uniqueness
 * check; the email is copied from Firebase Auth, which only changes after
 * the user confirms the new address (verifyBeforeUpdateEmail).
 */
import {normalizePhone} from "./delegate_login_logic";
import {isStaffRole} from "./staff_phone_lookup_logic";

export type ContactField = "phone" | "email";

export interface ContactRequest {
  field: ContactField;
  /** Normalized phone (field "phone" only). */
  phone?: string;
}

export interface Denial {
  code: "invalid-argument" | "permission-denied" | "failed-precondition" | "already-exists" | "not-found";
  reason: string;
  message: string;
}

export function isDenial(x: unknown): x is Denial {
  return typeof x === "object" && x !== null && "reason" in x && "code" in x;
}

/** Egyptian mobile, 11 digits after normalizePhone (010/011/012/015). */
export const EG_MOBILE_RE = /^01[0125]\d{8}$/;

export function parseContactRequest(data: unknown): ContactRequest | Denial {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const field = d.field;
  if (field === "email") return {field: "email"};
  if (field !== "phone") {
    return {code: "invalid-argument", reason: "bad_field", message: "field must be phone or email."};
  }
  const raw = typeof d.value === "string" ? d.value : "";
  const phone = normalizePhone(raw);
  if (!EG_MOBILE_RE.test(phone)) {
    return {code: "invalid-argument", reason: "bad_phone", message: "Enter a valid Egyptian mobile number."};
  }
  return {field: "phone", phone};
}

/**
 * Only staff accounts (staff token, users doc with a staff role) change
 * their contact here. Delegates change their phone through the OTP flow
 * (TAS-112), never this callable.
 */
export function callerAllowed(tokenRole: unknown, userDoc: Record<string, unknown> | undefined): Denial | null {
  if (tokenRole === "delegate") {
    return {code: "permission-denied", reason: "delegate_token", message: "Delegates cannot use this."};
  }
  if (!userDoc) {
    return {code: "not-found", reason: "no_user_doc", message: "Account not found."};
  }
  if (!isStaffRole(userDoc.role)) {
    return {code: "permission-denied", reason: "not_staff", message: "Staff accounts only."};
  }
  return null;
}

/** Another users doc already holds this phone (any stored format). */
export function phoneTakenByOther(callerUid: string, holderUids: string[]): boolean {
  return holderUids.some((uid) => uid !== callerUid);
}

/** The users doc patch for a confirmed Auth email. */
export function emailPatch(authEmail: string | undefined | null): {email: string} | Denial {
  const email = (authEmail ?? "").trim().toLowerCase();
  if (!email) {
    return {code: "failed-precondition", reason: "no_auth_email", message: "The account has no email."};
  }
  return {email};
}
