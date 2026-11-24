import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {isDenial, parseScope, personName} from "./supervisor_cards_logic";
import {
  buildPenaltyDoc,
  callerDelegateIds,
  isActiveDelegate,
  isSupervisorPosition,
  parsePenaltyInput,
} from "./supervisor_penalty_logic";

/**
 * createSupervisorPenalty (TAS-320)
 *
 * A supervisor delegate (delegate token, position Supervisor in that company)
 * records a penalty on another delegate of the same company. The rules do not
 * let a delegate token write penalties, so the server does it. The penalty is
 * ISSUED at once and the HR payroll deducts it in the month it was created.
 * onPenaltyCreated notifies the organization's managers.
 *
 * Request: { organizationUID?, companyUID?, targetDelegateId, title, category,
 *            incidentDescription?, fineAmount, branchId?, branchName? }
 * Response: { ok: true, penaltyId }
 *
 *   firebase deploy --project <id> --only functions:tashil-mobile-notifications:createSupervisorPenalty
 */
export const createSupervisorPenalty = functions
  .region("us-central1")
  .https.onCall(async (data: unknown, context) => {
    const token = context.auth?.token as Record<string, unknown> | undefined;
    const scope = parseScope(data, token);
    if (isDenial(scope)) {
      throw new functions.https.HttpsError(scope.code, scope.message, {reason: scope.reason});
    }
    const input = parsePenaltyInput(data);
    if ("error" in input) {
      throw new functions.https.HttpsError("invalid-argument", input.error);
    }
    const db = admin.firestore();
    const companyRef = db.collection("organizations").doc(scope.organizationUID)
      .collection("companies").doc(scope.companyUID);
    const delegates = companyRef.collection("delegates");

    // The caller must be a supervisor delegate of this company.
    const ids = callerDelegateIds(context.auth?.uid ?? "", token);
    let supervisor: {id: string; data: Record<string, unknown>} | null = null;
    for (const id of ids) {
      const snap = await delegates.doc(id).get();
      const d = snap.data();
      if (snap.exists && d && isSupervisorPosition(d.position) && isActiveDelegate(d)) {
        supervisor = {id: snap.id, data: d};
        break;
      }
    }
    if (!supervisor) {
      throw new functions.https.HttpsError("permission-denied", "إضافة الجزاء للمشرف بس.",
        {reason: "not_supervisor"});
    }
    if (ids.includes(input.targetDelegateId)) {
      throw new functions.https.HttpsError("invalid-argument", "ماينفعش تضيف جزاء على نفسك.",
        {reason: "self"});
    }
    const targetSnap = await delegates.doc(input.targetDelegateId).get();
    const target = targetSnap.data();
    if (!targetSnap.exists || !target || !isActiveDelegate(target)) {
      throw new functions.https.HttpsError("not-found", "المندوب مش موجود في شركتك.",
        {reason: "target_not_in_company"});
    }
    const companySnap = await companyRef.get();
    const company = companySnap.data() || {};

    const doc = buildPenaltyDoc({
      input,
      organizationUID: scope.organizationUID,
      companyUID: scope.companyUID,
      companyName: String(company.name || target.companyName || ""),
      supervisorId: supervisor.id,
      supervisorName: personName(supervisor.data),
      supervisorPhone: String(supervisor.data.phoneNumber || supervisor.data.phone || ""),
      targetName: personName(target),
    });
    const ref = db.collection("penalties").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.set({...doc, penaltyId: ref.id, createdAt: now, updatedAt: now, issuedAt: now});
    functions.logger.info("createSupervisorPenalty", {
      penaltyId: ref.id, companyUID: scope.companyUID, supervisorId: supervisor.id,
      targetDelegateId: input.targetDelegateId, fineAmount: input.fineAmount,
    });
    return {ok: true, penaltyId: ref.id};
  });
