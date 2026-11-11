import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {runSubscriptionSuspension, expireAbandonedRenewals, finalizeRenewalOnStatusChange} from "./subscription_jobs";
import {TIME_ZONE} from "./subscription_logic";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * 00:05 Cairo every day. On 1 Jan / 1 Jul this suspends every app-added
 * delegate without a paid subscription for the new period; on other days it
 * is a cheap re-check (idempotent).
 *
 * Not deployed to prod or tashil-dev from Phase 2 item 3. The job now uses
 * holds.ts in shadow mode; do not deploy this function until Mohamed says
 * to, and never together with a HOLDS_AUTHORITY_MODE flip. Do not deploy
 * it together with expireAbandonedSubscriptionRenewals unless there is a
 * separate written go.
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

/**
 * 00:10 Cairo every day. Expires abandoned pending renewals whose checkout
 * TTL (60 minutes by default) or Cairo-month quote window has passed, and
 * finishes rejected/cancelled renewals still payment-pending, freeing coverage.
 * The 15-minute reconcileSubscriptionPaymentsScheduled job is the primary
 * sweeper; this daily run is a backstop.
 */
export const expireAbandonedSubscriptionRenewals = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "256MB"})
  .pubsub.schedule("10 0 * * *")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    const res = await expireAbandonedRenewals(admin.firestore(), new Date());
    console.log(JSON.stringify({event: "expire_abandoned_renewals", ...res}));
    return null;
  });

/**
 * When staff reject or cancel a renewal, set paymentStatus to a terminal
 * state and release coverage so those delegates can be renewed again.
 */
export const finalizeSubscriptionRenewalOnStatus = functions
  .region("us-central1")
  .firestore.document("delegate_requests/{requestId}")
  .onUpdate(async (change) => {
    await finalizeRenewalOnStatusChange(
      admin.firestore(),
      change.after.id,
      (change.before.data() || {}) as Record<string, unknown>,
      (change.after.data() || {}) as Record<string, unknown>,
    );
    return null;
  });

/**
 * Every 15 minutes. Auto-expires awaiting-payment renewals that passed the
 * checkout TTL so no request stays pending forever, and releases coverage
 * so the user can retry or start a new request.
 */
export const reconcileSubscriptionPaymentsScheduled = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "256MB"})
  .pubsub.schedule("every 15 minutes")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    const res = await expireAbandonedRenewals(admin.firestore(), new Date());
    console.log(JSON.stringify({event: "reconcile_subscription_payments", ...res}));
    return null;
  });
