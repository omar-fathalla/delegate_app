/**
 * markForgottenAttendance (TAS-362): hourly job.
 *
 * Marks check-ins with no check-out 11.5 h after they started as
 * `missingCheckOut: true` (zero hours until HR sets the check-out) and sends
 * the delegate one notification per session. Both attendance paths are
 * covered by one collection-group query (type + timestamp window); the open
 * ones are picked in code because Firestore cannot query a missing field.
 *
 * Idempotent: a transaction re-checks the record before writing, and the
 * notification id is fixed (missing_checkout_<checkInId>).
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:markForgottenAttendance
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {isForgotten, markFields, notificationFor, window} from "./attendance_forgotten_logic";

if (admin.apps.length === 0) admin.initializeApp();

function toMs(v: unknown): number | null {
  return v instanceof admin.firestore.Timestamp ? v.toMillis() : null;
}

/** One run. Exported for the emulator test. */
export async function markForgottenAttendanceRun(
  db: FirebaseFirestore.Firestore,
  nowMs: number,
): Promise<{scanned: number; marked: number}> {
  const {fromMs, toMs: untilMs} = window(nowMs);
  const snap = await db.collectionGroup("attendance_logs")
    .where("type", "==", "check_in")
    .where("timestamp", ">=", admin.firestore.Timestamp.fromMillis(fromMs))
    .where("timestamp", "<=", admin.firestore.Timestamp.fromMillis(untilMs))
    .get();

  let marked = 0;
  for (const d of snap.docs) {
    if (!isForgotten(d.data(), toMs(d.data().timestamp), nowMs)) continue;
    const done = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(d.ref);
      const data = fresh.data();
      // Closed meanwhile (delegate, HR, or an old app build): leave it.
      if (!fresh.exists || !isForgotten(data, toMs(data?.timestamp), nowMs)) return false;
      tx.update(d.ref, {
        ...markFields(),
        missingCheckOutAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      const n = notificationFor(d.id, data);
      if (n) {
        tx.set(db.collection("notifications").doc(n.id), {
          ...n.doc,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      return true;
    });
    if (done) marked++;
  }
  return {scanned: snap.size, marked};
}

export const markForgottenAttendance = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 300, memory: "256MB"})
  .pubsub.schedule("every 60 minutes")
  .timeZone("Africa/Cairo")
  .onRun(async () => {
    const res = await markForgottenAttendanceRun(admin.firestore(), Date.now());
    functions.logger.info("markForgottenAttendance", res);
    return null;
  });
