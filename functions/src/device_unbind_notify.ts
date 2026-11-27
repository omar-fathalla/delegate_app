/**
 * onDeviceUnbindRequestCreated (TAS-367): notifies the delegate's company
 * supervisors when a device-change request is created. The push itself goes
 * out from onNotificationCreated (supervisor broadcast, TAS-211).
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:onDeviceUnbindRequestCreated
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {unbindRequestNotification} from "./device_unbind_notify_logic";

if (admin.apps.length === 0) admin.initializeApp();

export const onDeviceUnbindRequestCreated = functions.firestore
  .document("device_unbind_requests/{requestId}")
  .onCreate(async (snap, context) => {
    const n = unbindRequestNotification(context.params.requestId as string, snap.data());
    if (!n) return;
    try {
      await admin.firestore().collection("notifications").doc(n.id).create({
        ...n.doc,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Already sent (a retried event): nothing to do.
      if ((e as {code?: number}).code !== 6) throw e;
    }
  });
