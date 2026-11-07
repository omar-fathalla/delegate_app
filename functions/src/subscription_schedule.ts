import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {runSubscriptionSuspension} from "./subscription_jobs";
import {TIME_ZONE} from "./subscription_logic";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * 00:05 Cairo every day. On 1 Jan / 1 Jul this suspends every app-added
 * delegate without a paid subscription for the new period; on other days it
 * is a cheap re-check (idempotent).
 */
export const suspendExpiredSubscriptions = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("5 0 * * *")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    await runSubscriptionSuspension(admin.firestore(), new Date());
    return null;
  });
