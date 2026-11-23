/**
 * TAS-80: tokens FCM reports as dead (app uninstalled, token rotated) stayed in
 * fcm_tokens/{uid} forever, so every later push to that user failed the same
 * way. Delete the doc when FCM says its token is dead, but only if the doc
 * still holds that exact token (a new login may have written a fresh one).
 *
 * TAS-258: a user can have several devices. The app writes one doc per
 * install at fcm_tokens/{uid}/devices/{deviceId} and keeps writing the legacy
 * fcm_tokens/{uid} doc (old app versions write only the legacy doc).
 * tokensForUser() reads both; each token carries the docs that hold it, so a
 * dead token is pruned from the right doc(s) only.
 */
import type * as admin from "firebase-admin";

const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/** FCM's limit for one sendEachForMulticast call. */
export const MULTICAST_LIMIT = 500;

export function isDeadTokenError(err: unknown): boolean {
  const code = (err as {code?: unknown} | null)?.code;
  return typeof code === "string" && DEAD_TOKEN_CODES.has(code);
}

/** One push target: a token and the docs that currently hold it. */
export interface UserToken {
  uid: string;
  token: string;
  refs: admin.firestore.DocumentReference[];
}

function legacyRef(db: admin.firestore.Firestore, uid: string) {
  return db.collection("fcm_tokens").doc(uid);
}

function tokenOf(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/**
 * Unique tokens of [uid]: every fcm_tokens/{uid}/devices/* doc plus the legacy
 * fcm_tokens/{uid}.token. When the legacy doc holds the same token as a device
 * doc, the token is listed once with both refs.
 */
export async function tokensForUser(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<UserToken[]> {
  if (!uid) return [];
  const legacy = legacyRef(db, uid);
  const [devices, legacySnap] = await Promise.all([
    legacy.collection("devices").get(),
    legacy.get(),
  ]);
  const byToken = new Map<string, UserToken>();
  const add = (token: string, ref: admin.firestore.DocumentReference) => {
    if (!token) return;
    const cur = byToken.get(token);
    if (cur) cur.refs.push(ref);
    else byToken.set(token, {uid, token, refs: [ref]});
  };
  for (const doc of devices.docs) add(tokenOf(doc.get("token")), doc.ref);
  if (legacySnap.exists) add(tokenOf(legacySnap.get("token")), legacy);
  return Array.from(byToken.values());
}

/** tokensForUser for many users; a token shared by two users is sent once. */
export async function tokensForUsers(
  db: admin.firestore.Firestore,
  uids: string[],
): Promise<UserToken[]> {
  const lists = await Promise.all(Array.from(new Set(uids)).map((uid) => tokensForUser(db, uid)));
  const seen = new Set<string>();
  const out: UserToken[] = [];
  for (const t of lists.flat()) {
    if (seen.has(t.token)) continue;
    seen.add(t.token);
    out.push(t);
  }
  return out;
}

/**
 * Deletes each doc in [refs] (default: the legacy fcm_tokens/{uid}) that still
 * holds [token]. Returns true if anything was deleted.
 */
export async function pruneDeadToken(
  db: admin.firestore.Firestore,
  uid: string,
  token: string,
  refs?: admin.firestore.DocumentReference[],
): Promise<boolean> {
  if (!uid || !token) return false;
  const targets = refs && refs.length ? refs : [legacyRef(db, uid)];
  return db.runTransaction(async (tx) => {
    const snaps = await Promise.all(targets.map((r) => tx.get(r)));
    let deleted = false;
    snaps.forEach((snap, i) => {
      if (!snap.exists || snap.get("token") !== token) return;
      tx.delete(targets[i]);
      deleted = true;
    });
    return deleted;
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
  refs?: admin.firestore.DocumentReference[],
): Promise<boolean> {
  try {
    await messaging.send(message);
    return true;
  } catch (err) {
    if (!isDeadTokenError(err)) throw err;
    const pruned = await pruneDeadToken(db, uid, message.token, refs);
    console.log(`FCM token for ${uid} is dead; pruned=${pruned}`);
    return false;
  }
}

/** After sendEachForMulticast: prunes every recipient whose token is dead. */
export async function pruneDeadFromMulticast(
  db: admin.firestore.Firestore,
  recipients: Array<{uid: string; token: string; refs?: admin.firestore.DocumentReference[]}>,
  response: {responses: Array<{success: boolean; error?: unknown}>},
): Promise<number> {
  let pruned = 0;
  for (let i = 0; i < response.responses.length && i < recipients.length; i++) {
    const r = response.responses[i];
    if (r.success || !isDeadTokenError(r.error)) continue;
    const {uid, token, refs} = recipients[i];
    if (await pruneDeadToken(db, uid, token, refs)) pruned++;
  }
  return pruned;
}

export type PushMessaging = Pick<admin.messaging.Messaging, "send" | "sendEachForMulticast">;

/**
 * Sends [message] (no token) to every target with sendEachForMulticast, in
 * chunks of 500, and prunes dead tokens. Returns the number delivered.
 */
export async function sendMulticastAndPrune(
  db: admin.firestore.Firestore,
  messaging: Pick<admin.messaging.Messaging, "sendEachForMulticast">,
  targets: UserToken[],
  message: Omit<admin.messaging.MulticastMessage, "tokens">,
): Promise<number> {
  let delivered = 0;
  for (let i = 0; i < targets.length; i += MULTICAST_LIMIT) {
    const chunk = targets.slice(i, i + MULTICAST_LIMIT);
    const res = await messaging.sendEachForMulticast({...message, tokens: chunk.map((t) => t.token)});
    delivered += res.responses.filter((r) => r.success).length;
    await pruneDeadFromMulticast(db, chunk, res);
  }
  return delivered;
}

/**
 * Sends [message] to every device of one user. One token: messaging.send,
 * exactly as before (other errors are rethrown). Several: sendEachForMulticast.
 * Returns the number of devices reached.
 */
export async function sendToUserTokens(
  db: admin.firestore.Firestore,
  messaging: PushMessaging,
  targets: UserToken[],
  message: Omit<admin.messaging.MulticastMessage, "tokens">,
): Promise<number> {
  if (targets.length === 0) return 0;
  if (targets.length === 1) {
    const t = targets[0];
    const ok = await sendToUserToken(db, messaging, t.uid, {...message, token: t.token}, t.refs);
    return ok ? 1 : 0;
  }
  return sendMulticastAndPrune(db, messaging, targets, message);
}
