/**
 * TAS-229: named notifications to the managers of a new penalty's
 * organization. The app cannot read those users when the penalty is
 * recorded by company staff (HR, supervisors), so the server does it.
 * FCM is left to onNotificationCreated, like task_notify.
 *
 * Deploy (named only, tashil-dev first, prod with the combined release):
 *   functions:tashil-mobile-notifications:onPenaltyCreated
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  ManagerUser,
  penaltyManagerNotification,
  penaltyManagerNotificationId,
  penaltyManagerRecipients,
  penaltyOrganizationId,
} from "./penalty_notify_logic";

if (admin.apps.length === 0) admin.initializeApp();

async function loadOrganizationUsers(
  db: FirebaseFirestore.Firestore,
  org: string,
): Promise<ManagerUser[]> {
  const users = db.collection("users");
  const [single, multi] = await Promise.all([
    users.where("organizationUID", "==", org).get(),
    users.where("organizationUIDs", "array-contains", org).get(),
  ]);
  return [...single.docs, ...multi.docs].map((d) => ({id: d.id, data: d.data()}));
}

export const onPenaltyCreated = functions.firestore
  .document("penalties/{penaltyId}")
  .onCreate(async (snap, context) => {
    const penaltyId = context.params.penaltyId as string;
    const penalty = snap.data() || {};
    const org = penaltyOrganizationId(penalty);
    if (!org) {
      functions.logger.info("onPenaltyCreated: no organization", {penaltyId});
      return;
    }
    const db = admin.firestore();
    const recipients = penaltyManagerRecipients(await loadOrganizationUsers(db, org), penalty);
    let written = 0;
    for (const r of recipients) {
      const ref = db.collection("notifications").doc(penaltyManagerNotificationId(penaltyId, r.uid));
      try {
        await ref.create({
          ...penaltyManagerNotification(penaltyId, penalty, r),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        written++;
      } catch (e) {
        // ALREADY_EXISTS on a retried event: that manager was notified.
        if ((e as {code?: number}).code !== 6) throw e;
      }
    }
    functions.logger.info("onPenaltyCreated", {penaltyId, recipients: recipients.length, written});
  });
