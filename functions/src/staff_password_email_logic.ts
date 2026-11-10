import {canSendStaffInvite} from "./password_email_template";
import {staffCreateEnabled} from "./staff_accounts_logic";

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
