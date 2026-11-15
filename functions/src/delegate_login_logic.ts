import * as crypto from "crypto";

/**
 * Pure helpers for delegateLoginV2.
 *
 * Phone and national-ID normalization is intentionally tolerant of the
 * formats already stored on delegate documents (local 01…, +20, 0020,
 * Arabic/Persian digits, spaces and dashes). No document rewrite is required
 * for a delegate to sign in.
 */

const ARABIC_DIGITS = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"];
const PERSIAN_DIGITS = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"];
const ENGLISH_DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];

export const RATE_LIMIT_MAX_FAILURES = 5;
export const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
export const RATE_LIMIT_LOCK_MS = 15 * 60 * 1000;

/** Statuses that must not receive a delegate custom token. */
const DENIED_STATUSES = new Set([
  "pending",
  "suspended",
  "rejected",
  "blocked",
  "inactive",
  "disabled",
  "banned",
]);

const NATIONAL_ID_FIELDS = [
  "nationalityID",
  "nationalityId",
  "nationalId",
  "nationalID",
  "national_id",
  "idNumber",
];

const PHONE_FIELDS = ["phoneNumber", "phone", "mobile", "mobileNumber"];

export interface RateLimitState {
  failCount: number;
  windowStartMs: number;
  lockedUntilMs: number;
}

export interface DelegateCandidate {
  id: string;
  status: unknown;
  companyId: string;
  orgId: string;
  createdAtMillis: number | null;
  nationalIdMatches: boolean;
  /** Normalized phone. Copied into the custom token so rules can scope phone queries. */
  phone?: string;
  /** Firestore path of the delegate document, used to mirror the bound device. */
  path?: string;
  /** Legacy client-written binding. Used only when deviceBindings/{uid} is absent. */
  boundDeviceId?: string;
  boundDeviceModel?: string;
  fullName?: string;
}

export type CandidateDecision =
  | { outcome: "ok"; primary: DelegateCandidate; ids: string[] }
  | { outcome: "not_found" }
  | { outcome: "bad_credentials" }
  | { outcome: "inactive" };

function swapDigits(value: string): string {
  let normalized = value;
  for (let i = 0; i < ENGLISH_DIGITS.length; i++) {
    normalized = normalized.split(ARABIC_DIGITS[i]).join(ENGLISH_DIGITS[i]);
    normalized = normalized.split(PERSIAN_DIGITS[i]).join(ENGLISH_DIGITS[i]);
  }
  return normalized;
}

/** Same shape as the Flutter login normalizer, plus Persian digits. */
export function normalizePhone(phone: string): string {
  let normalized = swapDigits(phone.trim()).replace(/[^\d+]/g, "");

  if (normalized.startsWith("+20")) {
    normalized = "0" + normalized.substring(3);
  } else if (normalized.startsWith("+2")) {
    normalized = normalized.substring(2);
  } else if (normalized.startsWith("0020")) {
    normalized = "0" + normalized.substring(4);
  } else if (normalized.startsWith("002")) {
    normalized = normalized.substring(3);
  }

  if (normalized.length === 10 && /^1[0125]/.test(normalized)) {
    normalized = "0" + normalized;
  }

  return normalized;
}

/** Lookup variants so existing docs do not need a phone-format backfill. */
export function phoneQueryVariants(normalizedPhone: string): string[] {
  const variants = new Set<string>();
  if (!normalizedPhone) return [];
  variants.add(normalizedPhone);
  if (normalizedPhone.startsWith("0") && normalizedPhone.length === 11) {
    const withoutZero = normalizedPhone.substring(1);
    variants.add(withoutZero);
    variants.add("20" + withoutZero);
    variants.add("+20" + withoutZero);
    variants.add("0020" + withoutZero);
    variants.add("+2" + normalizedPhone);
    variants.add("002" + normalizedPhone);
  }
  return Array.from(variants);
}

export function normalizeNationalId(value: string): string {
  return swapDigits(value.trim()).replace(/[\s-]/g, "");
}

export function validateLoginInput(
  phoneRaw: unknown,
  nationalIdRaw: unknown,
): { ok: true; phone: string; nationalId: string } | { ok: false; reason: string } {
  if (typeof phoneRaw !== "string" || phoneRaw.trim() === "") {
    return { ok: false, reason: "missing_phone" };
  }
  if (phoneRaw.length > 32) {
    return { ok: false, reason: "invalid_phone" };
  }
  const phone = normalizePhone(phoneRaw);
  if (!/^\d{10,15}$/.test(phone)) {
    return { ok: false, reason: "invalid_phone" };
  }

  if (typeof nationalIdRaw !== "string" || nationalIdRaw.trim() === "") {
    return { ok: false, reason: "missing_national_id" };
  }
  if (nationalIdRaw.length > 32) {
    return { ok: false, reason: "invalid_national_id" };
  }
  const nationalId = normalizeNationalId(nationalIdRaw);
  if (nationalId.length < 6 || nationalId.length > 20) {
    return { ok: false, reason: "invalid_national_id" };
  }

  return { ok: true, phone, nationalId };
}

export function isLoginDenied(status: unknown): boolean {
  if (status == null) return false;
  const value = String(status).trim().toLowerCase();
  if (!value) return false;
  return DENIED_STATUSES.has(value);
}

export function nationalIdsMatch(stored: string, provided: string): boolean {
  const left = Buffer.from(normalizeNationalId(stored), "utf8");
  const right = Buffer.from(normalizeNationalId(provided), "utf8");
  if (left.length === 0 || right.length === 0) return false;
  if (left.length !== right.length) {
    crypto.timingSafeEqual(left, left);
    return false;
  }
  return crypto.timingSafeEqual(left, right);
}

export function extractNationalId(data: Record<string, unknown>): string {
  for (const key of NATIONAL_ID_FIELDS) {
    const value = data[key];
    if (typeof value === "string" && value.trim()) return value;
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

export function extractPhone(data: Record<string, unknown>): string {
  for (const key of PHONE_FIELDS) {
    const value = data[key];
    if (typeof value === "string" && value.trim()) return value;
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

export function readString(data: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

export function createdAtMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  if (typeof value === "object" && value !== null && "toMillis" in value) {
    const toMillis = (value as { toMillis?: unknown }).toMillis;
    if (typeof toMillis === "function") {
      const millis = (toMillis as () => number).call(value);
      return typeof millis === "number" && Number.isFinite(millis) ? millis : null;
    }
  }
  return null;
}

export function idsFromDelegatePath(path: string): { orgId: string; companyId: string } {
  const parts = path.split("/");
  const orgId = parts.length >= 2 && parts[0] === "organizations" ? parts[1] : "";
  const companyId = parts.length >= 4 && parts[2] === "companies" ? parts[3] : "";
  return { orgId, companyId };
}

/**
 * Auth uid is the primary delegate document id so a later rules phase can
 * compare request.auth.uid to that document. Ids longer than Firebase Auth's
 * 128-character limit are replaced with a stable hash of the same id.
 */
export function stableDelegateAuthUid(delegateDocId: string): string {
  if (delegateDocId.length > 0 && delegateDocId.length <= 128) {
    return delegateDocId;
  }
  return crypto.createHash("sha256").update(delegateDocId).digest("hex");
}

export function selectPrimaryDelegate(candidates: DelegateCandidate[]): DelegateCandidate {
  const ordered = candidates.slice();
  ordered.sort((a, b) => {
    const aDenied = isLoginDenied(a.status) ? 1 : 0;
    const bDenied = isLoginDenied(b.status) ? 1 : 0;
    if (aDenied !== bDenied) return aDenied - bDenied;
    const aTime = a.createdAtMillis ?? Number.MAX_SAFE_INTEGER;
    const bTime = b.createdAtMillis ?? Number.MAX_SAFE_INTEGER;
    if (aTime !== bTime) return aTime - bTime;
    if (a.id < b.id) return -1;
    if (a.id > b.id) return 1;
    return 0;
  });
  return ordered[0];
}

function isSuspendedLoginStatus(status: unknown): boolean {
  const s = String(status ?? "").toLowerCase().trim();
  return s === "suspended" || s === "admin_suspend";
}

export function evaluateCandidates(candidates: DelegateCandidate[]): CandidateDecision {
  if (candidates.length === 0) return { outcome: "not_found" };
  const matched = candidates.filter((candidate) => candidate.nationalIdMatches);
  if (matched.length === 0) return { outcome: "bad_credentials" };
  // H-1: do not allow login via a newer active doc when another profile is suspended.
  if (matched.some((candidate) => isSuspendedLoginStatus(candidate.status))) {
    return { outcome: "inactive" };
  }
  const allowed = matched.filter((candidate) => !isLoginDenied(candidate.status));
  if (allowed.length === 0) return { outcome: "inactive" };
  const primary = selectPrimaryDelegate(allowed);
  const ids = allowed.map((candidate) => candidate.id).sort();
  return { outcome: "ok", primary, ids };
}

export function buildCustomClaims(
  primary: DelegateCandidate,
  ids: string[],
  deviceId?: string,
): Record<string, unknown> {
  const claims: Record<string, unknown> = {
    role: "delegate",
    delegateId: primary.id,
    delegateIds: ids,
  };
  if (primary.companyId) claims.companyId = primary.companyId;
  if (primary.orgId) claims.orgId = primary.orgId;
  if (primary.phone) {
    const phones = phoneQueryVariants(normalizePhone(primary.phone));
    if (phones.length > 0) claims.phones = phones;
  }
  if (deviceId) claims.deviceId = deviceId;
  return claims;
}

/**
 * Claims for every authorized profile. companyIds/orgIds are included only
 * when the delegate belongs to more than one company or organization.
 */
export function buildCustomClaimsForProfiles(
  profiles: DelegateCandidate[],
  primary: DelegateCandidate,
  ids: string[],
  deviceId?: string,
): Record<string, unknown> {
  const claims = buildCustomClaims(primary, ids, deviceId);
  const companyIds = Array.from(
    new Set(profiles.map((profile) => profile.companyId).filter((value) => value)),
  );
  const orgIds = Array.from(
    new Set(profiles.map((profile) => profile.orgId).filter((value) => value)),
  );
  if (companyIds.length > 1) claims.companyIds = companyIds;
  else delete claims.companyIds;
  if (orgIds.length > 1) claims.orgIds = orgIds;
  else delete claims.orgIds;
  return claims;
}

/** Firestore doc that turns server-side OTP enforcement on. Default off. */
export const OTP_ENFORCEMENT_DOC = "config/delegate_auth";
export const OTP_ENFORCEMENT_FIELD = "otpEnforcementEnabled";

/** True only for an explicit boolean true. Missing/invalid => false. */
export function parseOtpEnforcementEnabled(data: unknown): boolean {
  if (!data || typeof data !== "object") return false;
  const value = (data as Record<string, unknown>)[OTP_ENFORCEMENT_FIELD];
  return value === true;
}

/**
 * When enforcement is on, the login token carries otp_required=true and
 * otp_verified=false. Rules ignore otp_verified unless otp_required is true,
 * so existing tokens and enforcement-off logins keep working.
 */
export function applyOtpEnforcementClaims(
  claims: Record<string, unknown>,
  enforcementEnabled: boolean,
): Record<string, unknown> {
  const next = { ...claims };
  if (enforcementEnabled) {
    next.otp_required = true;
    next.otp_verified = false;
  } else {
    delete next.otp_required;
    delete next.otp_verified;
  }
  return next;
}

/** Auth phoneNumber is E.164; delegate claims.phones use local/intl variants. */
export function phoneMatchesDelegateClaims(
  authPhoneE164: string,
  claimPhones: unknown,
): boolean {
  if (typeof authPhoneE164 !== "string" || !authPhoneE164.trim()) return false;
  if (!Array.isArray(claimPhones) || claimPhones.length === 0) return false;
  const authNormalized = normalizePhone(authPhoneE164);
  if (!authNormalized) return false;
  const authVariants = new Set(phoneQueryVariants(authNormalized));
  authVariants.add(authPhoneE164.trim());
  for (const raw of claimPhones) {
    if (typeof raw !== "string" || !raw.trim()) continue;
    const stored = normalizePhone(raw);
    if (stored && (authVariants.has(stored) || authVariants.has(raw.trim()))) {
      return true;
    }
    for (const variant of phoneQueryVariants(stored)) {
      if (authVariants.has(variant)) return true;
    }
  }
  return false;
}

/**
 * Pure decision for confirmDelegateOtp. Caller supplies Auth user phone and
 * existing custom claims. Does not talk to Admin SDK.
 */
export type ConfirmDelegateOtpDecision =
  | { ok: true; nextClaims: Record<string, unknown> }
  | { ok: false; reason: "not_signed_in" | "not_delegate" | "phone_not_linked" | "phone_mismatch" };

export function decideConfirmDelegateOtp(input: {
  authPhone: string | null | undefined;
  claims: Record<string, unknown> | null | undefined;
}): ConfirmDelegateOtpDecision {
  const claims = input.claims && typeof input.claims === "object" ? { ...input.claims } : {};
  if (claims.role !== "delegate") {
    return { ok: false, reason: "not_delegate" };
  }
  const authPhone = typeof input.authPhone === "string" ? input.authPhone.trim() : "";
  if (!authPhone) {
    return { ok: false, reason: "phone_not_linked" };
  }
  if (!phoneMatchesDelegateClaims(authPhone, claims.phones)) {
    return { ok: false, reason: "phone_mismatch" };
  }
  claims.otp_verified = true;
  return { ok: true, nextClaims: claims };
}

export function lockStatus(
  state: RateLimitState | null,
  now: number,
): { locked: boolean; retryAfterSeconds: number } {
  if (!state || !state.lockedUntilMs || state.lockedUntilMs <= now) {
    return { locked: false, retryAfterSeconds: 0 };
  }
  return {
    locked: true,
    retryAfterSeconds: Math.max(1, Math.ceil((state.lockedUntilMs - now) / 1000)),
  };
}

export function recordFailedAttempt(
  state: RateLimitState | null,
  now: number,
): RateLimitState & { locked: boolean; retryAfterSeconds: number } {
  const current = lockStatus(state, now);
  if (current.locked && state) {
    return {
      failCount: state.failCount,
      windowStartMs: state.windowStartMs,
      lockedUntilMs: state.lockedUntilMs,
      locked: true,
      retryAfterSeconds: current.retryAfterSeconds,
    };
  }

  const inWindow = state != null && now - state.windowStartMs <= RATE_LIMIT_WINDOW_MS;
  const failCount = (inWindow && state ? state.failCount : 0) + 1;
  const locked = failCount >= RATE_LIMIT_MAX_FAILURES;
  return {
    failCount: locked ? 0 : failCount,
    windowStartMs: inWindow && state ? state.windowStartMs : now,
    lockedUntilMs: locked ? now + RATE_LIMIT_LOCK_MS : 0,
    locked,
    retryAfterSeconds: locked ? Math.ceil(RATE_LIMIT_LOCK_MS / 1000) : 0,
  };
}

export function clearedRateLimit(now: number): RateLimitState {
  return { failCount: 0, windowStartMs: now, lockedUntilMs: 0 };
}

export function rateLimitDocId(normalizedPhone: string): string {
  return crypto.createHash("sha256").update(normalizedPhone).digest("hex");
}

export type DeviceBindingAction =
  | { action: "bind"; deviceId: string; consumeRequestId: string | null }
  | { action: "allow"; deviceId: string }
  | { action: "mismatch"; boundDeviceId: string; pendingRequestId: string | null };

/**
 * Server-side device decision.
 *
 * An empty stored id is a legacy delegate with no binding: the first V2
 * login binds the calling device. A stored id comes from deviceBindings/{uid}
 * when that doc exists, otherwise from the delegate's boundDeviceId.
 * An approved, not-yet-consumed device_unbind_requests doc lets the next
 * login rebind. The device that is already bound does not consume it.
 */
export function decideDeviceBinding(input: {
  storedDeviceId: string;
  requestedDeviceId: string;
  approvedRequestId: string | null;
  pendingRequestId: string | null;
}): DeviceBindingAction {
  const stored = input.storedDeviceId.trim();
  const requested = input.requestedDeviceId.trim();
  if (!stored) {
    return {
      action: "bind",
      deviceId: requested,
      consumeRequestId: input.approvedRequestId,
    };
  }
  if (stored === requested) {
    return { action: "allow", deviceId: stored };
  }
  if (input.approvedRequestId) {
    return {
      action: "bind",
      deviceId: requested,
      consumeRequestId: input.approvedRequestId,
    };
  }
  return {
    action: "mismatch",
    boundDeviceId: stored,
    pendingRequestId: input.pendingRequestId,
  };
}

/** Stable per install. Required so a missing client cannot skip the check. */
export function validateDeviceId(
  raw: unknown,
): { ok: true; deviceId: string } | { ok: false; reason: "missing_device" | "invalid_device" } {
  if (typeof raw !== "string" || raw.trim() === "") {
    return { ok: false, reason: "missing_device" };
  }
  const deviceId = raw.trim();
  if (deviceId.length < 4 || deviceId.length > 128 || /[\u0000-\u001f]/.test(deviceId)) {
    return { ok: false, reason: "invalid_device" };
  }
  return { ok: true, deviceId };
}

export function optionalDeviceLabel(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw.trim().slice(0, 80);
}
