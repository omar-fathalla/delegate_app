import {canSendStaffInvite} from "./password_email_template";
import {staffCreateEnabled} from "./staff_accounts_logic";
import {rateLimitDocId} from "./delegate_login_logic";

export {staffCreateEnabled};

export interface CallerRoleLookup {
  getRoleByUid(uid: string): Promise<string | null>;
  getRolesByEmail(email: string): Promise<string[]>;
}

/**
 * Resolve the caller's staff role. Prefer users/{uid}. The email query is a
 * fallback only when the Auth email is verified — otherwise a spoofed or
 * unverified token email could inherit a privileged role.
 */
export async function resolveCallerRole(
  uid: string,
  email: string | undefined,
  emailVerified: boolean,
  lookup: CallerRoleLookup,
): Promise<string> {
  const byId = await lookup.getRoleByUid(uid);
  if (byId !== null) return byId;
  if (email && emailVerified === true) {
    const roles = await lookup.getRolesByEmail(email);
    return roles.find((r) => canSendStaffInvite(r)) || roles[0] || "";
  }
  return "";
}

export function staffCreateAllowed(env: Record<string, string | undefined>): boolean {
  return staffCreateEnabled(env);
}

/**
 * TAS-317: limits on password emails, on top of the per-phone lock that
 * requestStaffPasswordReset already has. Each limit is a fixed window counter
 * (the same math as the staffPhoneLookup IP window, `ipWindowNext`), stored in
 * PASSWORD_EMAIL_LIMIT_COLLECTION (client rules deny it, like the other
 * rate-limit collections). The target email counter is shared by both
 * callables, so an admin resend and a public reset count together.
 */
export const PASSWORD_EMAIL_LIMIT_COLLECTION = "staff_password_email_limits";
export const PASSWORD_EMAIL_WINDOW_MS = 60 * 60 * 1000;
/** Emails to one address per hour, from either callable. */
export const PASSWORD_EMAIL_MAX_PER_TARGET = 3;
/** Public reset requests from one IP per hour (every request counts). */
export const PASSWORD_RESET_MAX_PER_IP = 10;
/**
 * Setup emails one signed-in admin may send per hour. Keyed by the caller
 * uid, not the IP: admins share office Wi-Fi and invite staff in batches.
 */
export const PASSWORD_SETUP_MAX_PER_CALLER = 30;

export type PasswordEmailLimitKind = "email" | "ip" | "caller";

/** Doc id for one limit (sha256, so no raw email or IP is stored). Empty value → "". */
export function passwordEmailLimitKey(kind: PasswordEmailLimitKind, value: string): string {
  const v = (value || "").trim().toLowerCase();
  if (!v) return "";
  return rateLimitDocId(`${kind}:${v}`);
}
