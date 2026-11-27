/**
 * remindPendingLeaves (TAS-370, L-4): hourly job. Every leave request still
 * pending 24 hours after it was filed reminds the company's HR users and its
 * supervisors (broadcast, pushed by onNotificationCreated), once.
 *
 * Reads `status == pending` only (single-field index) and checks the age in
 * code: pending requests are few, so no composite index is needed.
 * Idempotent: notification ids are fixed and written with create().
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:remindPendingLeaves
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {isActiveHr, isOverdue, reminderNotifications} from "./leave_reminders_logic";

if (admin.apps.length === 0) admin.initializeApp();

function toMs(v: unknown): number | null {
  return v instanceof admin.firestore.Timestamp ? v.toMillis() : null;
}

/** One run. Exported for the emulator test. */
export async function remindPendingLeavesRun(
  db: FirebaseFirestore.Firestore,
  nowMs: number,
): Promise<{scanned: number; sent: number}> {
  const snap = await db.collection("leave_requests").where("status", "==", "pending").get();
  const hrByCompany = new Map<string, string[]>();
  let sent = 0;
  for (const d of snap.docs) {
    const data = d.data();
    if (!isOverdue(data, toMs(data.createdAt), nowMs)) continue;
    const companyUID = typeof data.companyUID === "string" ? data.companyUID.trim() : "";
    if (!companyUID) continue;
    let hr = hrByCompany.get(companyUID);
    if (!hr) {
      const users = await db.collection("users").where("companyUID", "==", companyUID).get();
      hr = users.docs.filter((u) => isActiveHr(u.data())).map((u) => u.id);
      hrByCompany.set(companyUID, hr);
    }
    for (const n of reminderNotifications(d.id, data, hr)) {
      try {
        await db.collection("notifications").doc(n.id).create({
          ...n.doc,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        sent++;
      } catch (e) {
        // Already reminded (an earlier run): nothing to do.
        if ((e as {code?: number}).code !== 6) throw e;
      }
    }
  }
  return {scanned: snap.size, sent};
}

export const remindPendingLeaves = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 300, memory: "256MB"})
  .pubsub.schedule("every 60 minutes")
  .timeZone("Africa/Cairo")
  .onRun(async () => {
    const res = await remindPendingLeavesRun(admin.firestore(), Date.now());
    functions.logger.info("remindPendingLeaves", res);
    return null;
  });
