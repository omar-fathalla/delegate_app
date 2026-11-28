/**
 * onLeaveRequestDecided / onUnbindRequestDecided (TAS-371): the delegate's
 * notification for a decision on its leave or device-change request, written
 * by the server. The push goes out from onNotificationCreated.
 *
 * Deploy (named only, tashil-dev first, then the app, prod with the release):
 *   functions:tashil-mobile-notifications:onLeaveRequestDecided
 *   functions:tashil-mobile-notifications:onUnbindRequestDecided
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {decisionNotification, RequestKind} from "./request_decision_notify_logic";

if (admin.apps.length === 0) admin.initializeApp();

/** Writes the decision notification once. Exported for the emulator test. */
export async function notifyDecision(
  db: FirebaseFirestore.Firestore,
  kind: RequestKind,
  requestId: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): Promise<boolean> {
  const n = decisionNotification(kind, requestId, before, after);
  if (!n) return false;
  try {
    await db.collection("notifications").doc(n.id).create({
      ...n.doc,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  } catch (e) {
    // ALREADY_EXISTS on a retried event: already sent.
    if ((e as {code?: number}).code !== 6) throw e;
    return false;
  }
}

export const onLeaveRequestDecided = functions.firestore
  .document("leave_requests/{requestId}")
  .onUpdate(async (change, context) => {
    await notifyDecision(admin.firestore(), "leave", context.params.requestId as string,
      change.before.data(), change.after.data());
  });

export const onUnbindRequestDecided = functions.firestore
  .document("device_unbind_requests/{requestId}")
  .onUpdate(async (change, context) => {
    await notifyDecision(admin.firestore(), "unbind", context.params.requestId as string,
      change.before.data(), change.after.data());
  });
