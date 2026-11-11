/**
 * Shadow/audit trigger: logs status or holds changes that did not go
 * through the hold authority, without correcting status.
 *
 * Deploy: functions:tashil-mobile-notifications:auditDelegateHoldShadow
 * Do not deploy suspendExpiredSubscriptions with this function.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {evaluateShadowAudit} from "./holds";

if (admin.apps.length === 0) admin.initializeApp();

export const auditDelegateHoldShadow = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .firestore.document("organizations/{orgId}/companies/{companyId}/delegates/{uid}")
  .onUpdate(async (change, context) => {
    const before = (change.before.data() || {}) as Record<string, unknown>;
    const after = (change.after.data() || {}) as Record<string, unknown>;
    const decision = evaluateShadowAudit(before, after);
    if (!decision.audit || !decision.payload) return null;
    await admin.firestore().collection("status_audit").add({
      ...decision.payload,
      orgId: context.params.orgId,
      companyId: context.params.companyId,
      uid: context.params.uid,
      path: change.after.ref.path,
      at: FieldValue.serverTimestamp(),
    });
    return null;
  });
