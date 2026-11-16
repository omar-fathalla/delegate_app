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
} from "./invite_email_index_logic";

export const onInviteEmailIndexSync = functions.region("us-central1").firestore
  .document("invites/{inviteId}")
  .onWrite(async (change, context) => {
    const db = admin.firestore();
    const inviteId = context.params.inviteId;
    const before = change.before.exists
      ? (change.before.data() as Record<string, unknown>)
      : undefined;
    const after = change.after.exists
      ? (change.after.data() as Record<string, unknown>)
      : undefined;

    const {oldEmail, newEmail} = inviteEmailChanged(before, after);
    const deletes: Promise<unknown>[] = [];

    if (oldEmail && (!after || oldEmail !== newEmail || after.status !== "pending")) {
      deletes.push(
        db.collection(INVITE_EMAIL_INDEX_COLLECTION).doc(oldEmail).delete().catch(() => undefined),
      );
    }

    if (after) {
      const body = inviteEmailIndexFromInvite(inviteId, after);
      if (body) {
        const ref = db.collection(INVITE_EMAIL_INDEX_COLLECTION).doc(newEmail);
        await Promise.all([
          ...deletes,
          ref.set({
            ...body,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }),
        ]);
        return;
      }
    }

    await Promise.all(deletes);
  });

/** Admin SDK helper when invites are written outside the invites trigger (tests/backfill). */
export async function writeInviteEmailIndex(
  db: admin.firestore.Firestore,
  inviteId: string,
  data: Record<string, unknown>,
): Promise<void> {
  const body = inviteEmailIndexFromInvite(inviteId, data);
  if (!body) return;
  const id = inviteEmailIndexDocId(data.email);
  if (!id) return;
  await db.collection(INVITE_EMAIL_INDEX_COLLECTION).doc(id).set({
    ...body,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}