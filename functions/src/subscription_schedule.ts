import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  runSubscriptionSuspension,
  runSubscriptionReminders,
  expireAbandonedRenewals,
  finalizeRenewalOnStatusChange,
} from "./subscription_jobs";
import {TIME_ZONE} from "./subscription_logic";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * 00:05 Cairo every day. After each period end, unpaid app-added delegates
 * suspend on 15 Jan and 15 Jul (Africa/Cairo), not on 1 Jan / 1 Jul; the
 * first 14 days of January and July are grace. On other days this is a cheap
 * re-check (idempotent).
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
 * 00:08 Cairo daily. On the reminder day (default 14 Cairo days before each
 * period end — 16 Jun and 17 Dec) notifies supervisors with app-added
 * delegates lacking paid coverage for the next period. Web-added delegates
 * are excluded. Not deployed with M1 until Mohamed signs off.
 */
export const remindSupervisorsBeforeSubscriptionPeriodEnd = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("8 0 * * *")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    const res = await runSubscriptionReminders(admin.firestore(), new Date());
    console.log(JSON.stringify({event: "remind_supervisors_subscription", ...res}));
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
