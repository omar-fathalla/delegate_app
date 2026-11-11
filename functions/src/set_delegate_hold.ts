/**
 * Callable setDelegateHold. Super-admin, technical support, org-admin,
 * and company admin / company supervisor (one role) only.
 * Flutter has no App Check yet, so this callable does not enforce it.
 *
 * Deploy: functions:tashil-mobile-notifications:setDelegateHold
 * Mode is process.env.HOLDS_AUTHORITY_MODE (default shadow). Flip or roll
 * back on tashil-dev with scripts/holds_authority_mode.sh — do not upload
 * source and do not deploy suspendExpiredSubscriptions with this function
 * or with a mode flip.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {applyHoldChange, HoldApplyError} from "./holds_apply";
import {
  decideSetDelegateHold,
  holdsMode,
  isHoldKey,
  isHoldOp,
  type HoldsCaller,
} from "./holds";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 30, memory: "256MB" as const};

function fail(code: functions.https.FunctionsErrorCode, reason: string): never {
  throw new functions.https.HttpsError(code, reason, {reason});
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

async function loadCaller(ctx: functions.https.CallableContext): Promise<HoldsCaller> {
  if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
    fail("unauthenticated", "sign_in_required");
  }
  const snap = await admin.firestore().collection("users").doc(ctx.auth.uid).get();
  if (!snap.exists) fail("permission-denied", "caller_not_staff");
  const d = (snap.data() || {}) as Record<string, unknown>;
  return {
    uid: ctx.auth.uid,
    role: d.role,
    organizationUID: d.organizationUID,
    companyUID: d.companyUID,
    isActive: d.isActive,
  };
}

export const setDelegateHold = functions.region("us-central1").runWith(opts).https.onCall(
  async (data, ctx) => {
    try {
      const caller = await loadCaller(ctx);
      const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
      const orgId = str(p.orgId) || str(p.organizationUID);
      const companyId = str(p.companyId) || str(p.companyUID);
      const uid = str(p.uid);
      const hold = p.hold;
      const op = p.op;
      const note = str(p.note);
      const requestId = str(p.requestId);
      const decision = decideSetDelegateHold(
        caller, {orgId, companyId}, hold, op, note,
      );
      if (!decision.ok) {
        const code = decision.reason === "invalid_hold" ||
          decision.reason === "invalid_op" ||
          decision.reason === "invalid_target" ||
          decision.reason === "note_required" ?
          "invalid-argument" : "permission-denied";
        fail(code, decision.reason);
      }
      if (!isHoldKey(hold) || !isHoldOp(op)) fail("invalid-argument", "invalid_hold");
      const plan = await applyHoldChange(admin.firestore(), {
        orgId, companyId, uid, op, hold,
        actor: caller.uid,
        note: note || undefined,
        requestId: requestId || undefined,
        source: "setDelegateHold",
      });
      return {
        ok: true,
        unchanged: !!plan.unchanged,
        reason: plan.reason || null,
        mode: plan.mode || holdsMode(),
        holds: plan.nextHolds,
        derivedStatus: plan.derivedStatus,
        statusVersion: plan.statusVersion,
      };
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      if (e instanceof HoldApplyError) {
        fail(e.httpCode, e.reason);
      }
      functions.logger.error("setDelegateHold failed", {message: String(e)});
      fail("internal", "unavailable");
    }
  },
);
