/**
 * Maintains invite_email_index/{lowercasedEmail} for C1 claimInvite$ batch correlation.
 *
 * Deploy (targeted):
 *   firebase deploy --only functions:tashil-mobile-notifications:onInviteEmailIndexSync --project <project>
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  INVITE_EMAIL_INDEX_COLLECTION,
  inviteEmailIndexDocId,
  inviteEmailIndexFromInvite,
  inviteEmailChanged,
  pickNewestPendingInvite,
} from "./invite_email_index_logic";

async function reconcileInviteEmailIndexForEmail(
  db: admin.firestore.Firestore,
  normalizedEmail: string,
): Promise<void> {
  if (!normalizedEmail) return;
  const snap = await db.collection("invites").where("status", "==", "pending").get();
  const pending = snap.docs
    .map((d) => ({inviteId: d.id, data: d.data() as Record<string, unknown>}))
    .filter((x) => inviteEmailIndexDocId(x.data.email) === normalizedEmail);
  const ref = db.collection(INVITE_EMAIL_INDEX_COLLECTION).doc(normalizedEmail);
  const winner = pickNewestPendingInvite(pending);
  if (!winner) {
    await ref.delete().catch(() => undefined);
    return;
  }
  const body = inviteEmailIndexFromInvite(winner.inviteId, winner.data);
  if (!body) {
    await ref.delete().catch(() => undefined);
    return;
  }
  await ref.set({
    ...body,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export const onInviteEmailIndexSync = functions.region("us-central1").firestore
  .document("invites/{inviteId}")
  .onWrite(async (change) => {
    const db = admin.firestore();
    const before = change.before.exists
      ? (change.before.data() as Record<string, unknown>)
      : undefined;
    const after = change.after.exists
      ? (change.after.data() as Record<string, unknown>)
      : undefined;

    const {oldEmail, newEmail} = inviteEmailChanged(before, after);
    const emails = new Set<string>();
    if (oldEmail) emails.add(oldEmail);
    if (newEmail) emails.add(newEmail);
    await Promise.all([...emails].map((em) => reconcileInviteEmailIndexForEmail(db, em)));
  });

/** Admin SDK helper when invites are written outside the invites trigger (tests/backfill). */
export async function writeInviteEmailIndex(
  db: admin.firestore.Firestore,
  inviteId: string,
  data: Record<string, unknown>,
): Promise<void> {
  const email = inviteEmailIndexDocId(data.email);
  if (!email) return;
  await reconcileInviteEmailIndexForEmail(db, email);
}