/**
 * respondToPenalty (TAS-365): the delegate acknowledges or disputes its
 * penalty, and a super admin / chain admin decides the dispute. The rules do
 * not let a delegate token update penalties (and the penalties block is near
 * the 1000-expression limit), so the server does it. Rules in
 * respond_to_penalty_logic.ts; notifications from onPenaltyUpdated.
 *
 * Request: { penaltyId, action: "acknowledge" | "dispute" | "resolve",
 *            reason?, decision?: "uphold" | "cancel" }
 * Response: { ok: true, status }
 *
 *   firebase deploy --project <id> --only functions:tashil-mobile-notifications:respondToPenalty
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {callerDelegateIds} from "./supervisor_penalty_logic";
import {isDenial, NOW, parseRespondInput, planResponse} from "./respond_to_penalty_logic";

if (admin.apps.length === 0) admin.initializeApp();

function withServerTime(update: Record<string, unknown>): Record<string, unknown> {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(update)) out[k] = v === NOW ? now : v;
  return out;
}

export const respondToPenalty = functions
  .region("us-central1")
  .https.onCall(async (data: unknown, context) => {
    const uid = context.auth?.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "سجّل دخولك الأول.");
    const token = context.auth?.token as Record<string, unknown> | undefined;
    const input = parseRespondInput(data);
    if (isDenial(input)) {
      throw new functions.https.HttpsError(input.code, input.message, {reason: input.reason});
    }
    const db = admin.firestore();
    const ref = db.collection("penalties").doc(input.penaltyId);
    let name = "";
    if (input.action === "resolve") {
      const u = (await db.collection("users").doc(uid).get()).data() || {};
      name = String(u.fullName || u.name || u.displayName || "").trim();
    }
    const caller = {uid, delegateIds: callerDelegateIds(uid, token), token, name};
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const plan = planResponse(input, snap.exists ? snap.data() || {} : null, caller, Date.now());
      if (isDenial(plan)) return plan;
      if (!plan.noop) tx.update(ref, withServerTime(plan.update) as FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>);
      return plan;
    });
    if (isDenial(result)) {
      throw new functions.https.HttpsError(result.code, result.message, {reason: result.reason});
    }
    functions.logger.info("respondToPenalty", {
      penaltyId: input.penaltyId, action: input.action, decision: input.decision,
      status: result.status, uid,
    });
    return {ok: true, status: result.status};
  });
