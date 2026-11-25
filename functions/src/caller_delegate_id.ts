/**
 * TAS-28 phase 0: who the caller is as a delegate.
 *
 * delegateLoginV2 puts the delegate document id in the `delegateId` claim
 * (and every profile id in `delegateIds`). Today the Auth uid is that same
 * id (`stableDelegateAuthUid`), so the old `uid == delegate doc id` check and
 * the claim give the same answer. Phase 1 gives new logins a different uid
 * (`dlg_<hash>`); code that reads the claim keeps working then, code that
 * reads the uid does not. Old tokens without the claim fall back to the uid.
 */

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isDelegateToken(token: Record<string, unknown> | undefined | null): boolean {
  return !!token && str(token.role) === "delegate";
}

/**
 * The caller's own delegate document id: the `delegateId` claim on a
 * delegate token, else the Auth uid (staff tokens and old tokens).
 */
export function callerDelegateId(
  uid: string | undefined | null,
  token: Record<string, unknown> | undefined | null,
): string {
  const claim = isDelegateToken(token) ? str(token?.delegateId) : "";
  return claim || str(uid);
}

/**
 * Every id that names the caller: the Auth uid (old equality, still
 * accepted in phase 0) and, on a delegate token, the `delegateId` claim.
 * Profile ids from `delegateIds` are not included: they are other copies of
 * the delegate, not the folder / path owner.
 */
export function callerSelfIds(
  uid: string | undefined | null,
  token: Record<string, unknown> | undefined | null,
): string[] {
  const ids = [str(uid), isDelegateToken(token) ? str(token?.delegateId) : ""];
  return [...new Set(ids.filter(Boolean))];
}
