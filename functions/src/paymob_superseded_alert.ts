import * as admin from "firebase-admin";
import {sendToUserToken} from "./fcm_token_cleanup";
import {
  PRIVILEGED_ALERT_ROLE_VALUES,
  privilegedAlertDoc,
  uniqueRecipientIds,
} from "./delegate_profile_edit_logic";

export const PAYMOB_SUPERSEDED_NOTIFICATION_TYPE = "paymob_superseded_payment";
const ADMIN_ALERTS = "admin_alerts";

export type PaymobMessaging = Pick<admin.messaging.Messaging, "send">;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function formatAmountEgp(amountCents: number, currency: string): string {
  const cur = str(currency).toUpperCase() || "EGP";
  const major = amountCents / 100;
  return `${major.toFixed(2)} ${cur}`;
}

async function privilegedRecipientUids(
  db: admin.firestore.Firestore,
): Promise<string[]> {
  const users = await db.collection("users").where("role", "in", [
    ...PRIVILEGED_ALERT_ROLE_VALUES,
  ]).get();
  return uniqueRecipientIds(users.docs.map((d) => d.id));
}

async function sendFcmTokenPush(
  db: admin.firestore.Firestore,
  messaging: PaymobMessaging,
  recipientUid: string,
  payload: {
    title: string;
    body: string;
    type: string;
    organizationId: string;
    companyId: string;
    requestId: string;
    attemptId: string;
    txId: string;
  },
): Promise<boolean> {
  const tokenDoc = await db.collection("fcm_tokens").doc(recipientUid).get();
  const token = str(tokenDoc.get("token"));
  if (!token) return false;
  return sendToUserToken(db, messaging, recipientUid, {
    token,
    notification: {title: payload.title, body: payload.body},
    android: {
      priority: "high",
      notification: {
        channelId: "task_notifications",
        sound: "default",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      payload: {aps: {sound: "default", badge: 1}},
    },
    data: {
      type: payload.type,
      organizationId: payload.organizationId,
      companyId: payload.companyId,
      requestId: payload.requestId,
      attemptId: payload.attemptId,
      paymobTransactionId: payload.txId,
    },
  });
}

export interface PaymobSupersededAlertResult {
  adminAlert: boolean;
  notifications: number;
  fcmSent: number;
}

/**
 * Platform alert for a superseded Paymob success (needs manual refund).
 * Writes `admin_alerts/{txId}`, privileged `notifications`, and FCM to staff tokens.
 */
export async function notifyPaymobSupersededPaymentRefund(
  db: admin.firestore.Firestore,
  opts: {
    requestId: string;
    attemptId: string;
    txId: string;
    amountCents: number;
    currency: string;
    companyUID: string;
    organizationUID: string;
    companyName?: string;
    messaging?: PaymobMessaging;
  },
): Promise<PaymobSupersededAlertResult> {
  const title = "دفعة مكررة — استرجاع مطلوب";
  const amountLabel = formatAmountEgp(opts.amountCents, opts.currency);
  const companyLabel = str(opts.companyName) || "شركة غير محددة";
  const body = [
    "دفعة مكررة محتاجة استرجاع.",
    `الشركة: ${companyLabel}`,
    `الطلب: ${opts.requestId}`,
    `المبلغ: ${amountLabel}`,
    `معاملة Paymob: ${opts.txId}`,
    `محاولة قديمة: ${opts.attemptId}`,
  ].join(" ");
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const alertRef = db.collection(ADMIN_ALERTS).doc(opts.txId);
  const alertData = {
    type: PAYMOB_SUPERSEDED_NOTIFICATION_TYPE,
    requestId: opts.requestId,
    attemptId: opts.attemptId,
    paymobTransactionId: opts.txId,
    companyUID: opts.companyUID,
    companyName: companyLabel,
    organizationUID: opts.organizationUID,
    organizationId: opts.organizationUID,
    amountCents: opts.amountCents,
    currency: opts.currency,
    needs_refund: true,
    createdAt: ts,
  };

  const created = await db.runTransaction(async (tx) => {
    const snap = await tx.get(alertRef);
    if (snap.exists) return false;
    tx.create(alertRef, alertData);
    return true;
  });
  if (!created) {
    return {adminAlert: true, notifications: 0, fcmSent: 0};
  }

  const recipientIds = await privilegedRecipientUids(db);
  if (!recipientIds.length) {
    return {adminAlert: true, notifications: 0, fcmSent: 0};
  }

  const batch = db.batch();
  for (const recipientUid of recipientIds) {
    const ref = db.collection("notifications").doc();
    batch.set(ref, {
      ...privilegedAlertDoc({
        recipientUid,
        title,
        body,
        type: PAYMOB_SUPERSEDED_NOTIFICATION_TYPE,
        senderName: "Paymob",
        senderRole: "system",
        companyUID: opts.companyUID,
        organizationUID: opts.organizationUID,
        requestId: opts.requestId,
      }),
      attemptId: opts.attemptId,
      paymobTransactionId: opts.txId,
      amountCents: opts.amountCents,
      currency: opts.currency,
      needs_refund: true,
      createdAt: ts,
    });
  }
  await batch.commit();

  let fcmSent = 0;
  const messaging = opts.messaging ?? admin.messaging();
  for (const recipientUid of recipientIds) {
    try {
      const sent = await sendFcmTokenPush(db, messaging, recipientUid, {
        title,
        body,
        type: PAYMOB_SUPERSEDED_NOTIFICATION_TYPE,
        organizationId: opts.organizationUID,
        companyId: opts.companyUID,
        requestId: opts.requestId,
        attemptId: opts.attemptId,
        txId: opts.txId,
      });
      if (sent) fcmSent += 1;
    } catch (err) {
      console.warn(JSON.stringify({
        event: "paymob_superseded_fcm_failed",
        recipientUid,
        txId: opts.txId,
      }));
    }
  }

  return {adminAlert: true, notifications: recipientIds.length, fcmSent};
}