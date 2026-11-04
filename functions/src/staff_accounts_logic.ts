/**
 * Pure helpers for createStaffUser / resendStaffSetupLink / claimInvite.
 *
 * Staff (admin) accounts only. Delegates keep phone + national ID login
 * through delegateLoginV2; nothing here creates or changes delegates.
 */
import {isStaffRole, normalizeRoleKey} from "./staff_phone_lookup_logic";

const SUPER = new Set(["super_admin", "superadmin"]);
const ORG_ADMIN = new Set(["organization_admin", "organizationadmin", "org_admin"]);
const TECH = new Set(["technical_support", "technicalsupport", "tech_support", "techsupport"]);
const COMPANY_ADMIN = new Set(["company_admin", "companyadmin", "admin"]);
const COMPANY_FIELD_MANAGER = new Set([
  "supervisor", "company_supervisor", "hr", "company_hr", "human_resources",
]);
// Matches firestore.rules companyCanGrant: a company admin may grant only
// supervisor/HR staff roles; supervisor/HR may grant field roles only, and
// field roles are never created here (delegate flow), so they get nothing.
const COMPANY_ADMIN_GRANTS = COMPANY_FIELD_MANAGER;
const FIELD = new Set(["delegate", "promoter", ""]);

export interface Caller {
  role: unknown;
  organizationUID?: unknown;
  companyUID?: unknown;
  isActive?: unknown;
}

export interface StaffTarget {
  role: string;
  organizationUID: string;
  companyUID: string;
}

export type Decision = {ok: true} | {ok: false; reason: string};

export function isSuperRole(role: unknown): boolean {
  return SUPER.has(normalizeRoleKey(role));
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Who may create (or resend a setup link for) which staff role. */
export function decideStaffCreate(caller: Caller | null, target: StaffTarget): Decision {
  if (!caller) return {ok: false, reason: "caller_not_staff"};
  if (caller.isActive === false) return {ok: false, reason: "caller_inactive"};
  const c = normalizeRoleKey(caller.role);
  const t = normalizeRoleKey(target.role);
  if (FIELD.has(t) || !isStaffRole(target.role)) return {ok: false, reason: "not_staff_role"};
  if (SUPER.has(t)) return {ok: false, reason: "super_admin_not_creatable"};
  if (COMPANY_ADMIN.has(t) && (!target.organizationUID || !target.companyUID)) {
    return {ok: false, reason: "company_required"};
  }
  if (SUPER.has(c)) return {ok: true};
  const co = str(caller.organizationUID);
  const cc = str(caller.companyUID);
  if (!co || target.organizationUID !== co) return {ok: false, reason: "out_of_scope"};
  if (TECH.has(t) || ORG_ADMIN.has(t)) return {ok: false, reason: "role_not_allowed"};
  if (ORG_ADMIN.has(c)) return {ok: true};
  if (COMPANY_FIELD_MANAGER.has(c)) return {ok: false, reason: "role_not_allowed"};
  if (COMPANY_ADMIN.has(c)) {
    if (!cc || target.companyUID !== cc) return {ok: false, reason: "out_of_scope"};
    if (!COMPANY_ADMIN_GRANTS.has(t)) return {ok: false, reason: "role_not_allowed"};
    return {ok: true};
  }
  return {ok: false, reason: "caller_not_allowed"};
}

export function normalizeEmail(raw: unknown): string {
  return str(raw).toLowerCase();
}

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}

export const SETUP_RATE_MAX = 5;
export const SETUP_RATE_WINDOW_MS = 60 * 60 * 1000;

/** Sliding counter per caller; returns the next state or null when over the limit. */
export function nextRate(
  prev: {count?: unknown; windowStart?: unknown} | undefined,
  now: number,
): {count: number; windowStart: number} | null {
  const ws = typeof prev?.windowStart === "number" ? prev.windowStart : 0;
  const count = typeof prev?.count === "number" ? prev.count : 0;
  if (now - ws >= SETUP_RATE_WINDOW_MS) return {count: 1, windowStart: now};
  if (count >= SETUP_RATE_MAX) return null;
  return {count: count + 1, windowStart: ws};
}

export interface InviteData {
  email?: unknown;
  roleToAssign?: unknown;
  organizationId?: unknown;
  companyId?: unknown;
  companyName?: unknown;
  status?: unknown;
  expiresAt?: unknown;
  claimedBy?: unknown;
  claimedByUid?: unknown;
  claimedAt?: unknown;
}

/** Server-side kill switch: createStaffUser/resendStaffSetupLink stay off
 * until the #204 rules are live (mail read lock + users write lock). Set
 * STAFF_CREATE_ENABLED=true in functions/.env.<project> to enable. */
export function staffCreateEnabled(env: Record<string, string | undefined>): boolean {
  return env.STAFF_CREATE_ENABLED === "true";
}

/** claimInvite checks (E1/H3): never claimed, pending, unexpired, email match, roleToAssign only. */
export function decideClaim(
  invite: InviteData | undefined,
  user: {email: string; emailVerified: boolean},
  nowMs: number,
  expiresAtMs: number | null,
): Decision {
  if (!invite) return {ok: false, reason: "invite_not_found"};
  if (!user.emailVerified) return {ok: false, reason: "email_not_verified"};
  if (invite.claimedBy || invite.claimedByUid || invite.claimedAt) {
    return {ok: false, reason: "invite_already_claimed"};
  }
  if (invite.status !== "pending") return {ok: false, reason: "invite_not_pending"};
  if (expiresAtMs === null || expiresAtMs <= nowMs) return {ok: false, reason: "invite_expired"};
  if (normalizeEmail(invite.email) !== normalizeEmail(user.email) || !user.email) {
    return {ok: false, reason: "email_mismatch"};
  }
  const role = invite.roleToAssign;
  if (role !== "org-admin" && role !== "company-admin") return {ok: false, reason: "role_not_allowed"};
  if (!str(invite.organizationId)) return {ok: false, reason: "invite_invalid"};
  if (role === "company-admin" && !str(invite.companyId)) return {ok: false, reason: "invite_invalid"};
  return {ok: true};
}

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (ch) => (
    {"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"}[ch] as string));
}

/** Setup email body. The link is only placed in the mail doc, never returned. */
export function setupEmail(displayName: string, link: string): {subject: string; html: string} {
  return {
    subject: "Tashil - تفعيل حسابك",
    html: `<div dir="rtl" style="font-family:Arial,sans-serif;max-width:600px;margin:auto">
<h2>مرحباً ${escapeHtml(displayName)}</h2>
<p>تم إنشاء حساب لك على منصة تسهيل. اضغط الرابط لتعيين كلمة السر ثم سجّل الدخول.</p>
<p><a href="${escapeHtml(link)}">تعيين كلمة السر</a></p>
<p style="color:#999;font-size:12px">الرابط صالح لفترة محدودة. لو انتهى اطلب من المسؤول إعادة الإرسال.</p>
</div>`,
  };
}
