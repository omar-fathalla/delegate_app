/**
 * TAS-80: tokens FCM reports as dead (app uninstalled, token rotated) stayed in
 * fcm_tokens/{uid} forever, so every later push to that user failed the same
 * way. Delete the doc when FCM says its token is dead, but only if the doc
 * still holds that exact token (a new login may have written a fresh one).
 */
import type * as admin from "firebase-admin";

const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export function isDeadTokenError(err: unknown): boolean {
  const code = (err as {code?: unknown} | null)?.code;
  return typeof code === "string" && DEAD_TOKEN_CODES.has(code);
}

/** Deletes fcm_tokens/{uid} if it still holds [token]. Returns true if deleted. */
export async function pruneDeadToken(
  db: admin.firestore.Firestore,
  uid: string,
  token: string,
): Promise<boolean> {
  if (!uid || !token) return false;
  const ref = db.collection("fcm_tokens").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get("token") !== token) return false;
    tx.delete(ref);
    return true;
  });
}

/**
 * Sends one message to one user's token. A dead token is pruned and the call
 * returns false instead of throwing; any other error is rethrown.
 */
export async function sendToUserToken(
  db: admin.firestore.Firestore,
  messaging: Pick<admin.messaging.Messaging, "send">,
  uid: string,
  message: admin.messaging.TokenMessage,
): Promise<boolean> {
  try {
    await messaging.send(message);
    return true;
  } catch (err) {
    if (!isDeadTokenError(err)) throw err;
    const pruned = await pruneDeadToken(db, uid, message.token);
    console.log(`FCM token for ${uid} is dead; pruned=${pruned}`);
    return false;
  }
}

/** After sendEachForMulticast: prunes every recipient whose token is dead. */
export async function pruneDeadFromMulticast(
  db: admin.firestore.Firestore,
  recipients: Array<{uid: string; token: string}>,
  response: {responses: Array<{success: boolean; error?: unknown}>},
): Promise<number> {
  let pruned = 0;
  for (let i = 0; i < response.responses.length && i < recipients.length; i++) {
    const r = response.responses[i];
    if (r.success || !isDeadTokenError(r.error)) continue;
    if (await pruneDeadToken(db, recipients[i].uid, recipients[i].token)) pruned++;
  }
  return pruned;
}
