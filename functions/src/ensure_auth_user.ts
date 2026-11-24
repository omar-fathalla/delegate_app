/**
 * TAS-303: the delegate's Auth user does not exist on its first login (the
 * app creates it with signInWithCustomToken). setCustomUserClaims then fails
 * with user-not-found, the claims live only in that session's token, and they
 * are gone as soon as the app links a phone (the token is re-minted from the
 * stored user). Create the user first so the claims are stored.
 */
export interface AuthLike {
  getUser(uid: string): Promise<unknown>;
  createUser(props: {uid: string}): Promise<unknown>;
  setCustomUserClaims(uid: string, claims: Record<string, unknown>): Promise<void>;
}

function codeOf(error: unknown): string {
  const e = error as {code?: unknown; errorInfo?: {code?: unknown}};
  return String(e?.code ?? e?.errorInfo?.code ?? "");
}

export async function storeDelegateClaims(
  auth: AuthLike,
  uid: string,
  claims: Record<string, unknown>,
): Promise<"stored" | "created_and_stored"> {
  let created = false;
  try {
    await auth.getUser(uid);
  } catch (error) {
    if (codeOf(error) !== "auth/user-not-found") throw error;
    try {
      await auth.createUser({uid});
      created = true;
    } catch (again) {
      // Another login created it meanwhile.
      if (codeOf(again) !== "auth/uid-already-exists") throw again;
    }
  }
  await auth.setCustomUserClaims(uid, claims);
  return created ? "created_and_stored" : "stored";
}
