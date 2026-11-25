/**
 * Callable approveDelegateDocuments (TAS-336).
 *
 * Technical support (and super-admin) approve a new_delegate /
 * add_organization request whose bound delegate docs already exist as
 * 'pending': one transaction moves the request to 'approved' and activates
 * every listed delegate doc with a status-only write (pending document
 * entries -> approved). The same write from the app was denied by the
 * rules' 1000-expression limit at 5+ document flips on one doc.
 *
 * Checks mirror firestore.rules exactly (approve_delegate_documents_logic.ts),
 * the role comes from token claims, time is server time. A retry after a
 * successful call returns {alreadyApproved: true} and writes nothing.
 *
 * App Check: monitoring only (TAS-16 step 1: nothing is enforced until the
 * user approves enforcement). A call without a token is logged.
 *
 * Deploy: functions:tashil-mobile-notifications:approveDelegateDocuments
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {
  alreadyApplied,
  approverRoleFromClaims,
  boundDelegateId,
  checkRequest,
  orgAllowed,
  parseInput,
  planActivation,
  reasonMessage,
  requestUrlMap,
} from "./approve_delegate_documents_logic";

const opts = {timeoutSeconds: 60, memory: "256MB" as const};

const CODE_FOR: Record<string, functions.https.FunctionsErrorCode> = {
  not_approver: "permission-denied",
  own_request: "permission-denied",
  org_not_in_request: "permission-denied",
  delegate_out_of_scope: "permission-denied",
  request_not_found: "not-found",
  delegate_not_found: "not-found",
};

function fail(reason: string, extra: Record<string, unknown> = {}): never {
  const code = CODE_FOR[reason] ?? "failed-precondition";
  throw new functions.https.HttpsError(code, reasonMessage(reason), {reason, ...extra});
}

export const approveDelegateDocuments = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new functions.https.HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً.", {reason: "sign_in_required"});
    }
    if (!ctx.app) console.warn("approveDelegateDocuments: no App Check token (monitoring only)");
    const role = approverRoleFromClaims(ctx.auth.token);
    if (!role) fail("not_approver");
    const parsed = parseInput(data);
    if (!parsed.ok) {
      throw new functions.https.HttpsError("invalid-argument", "بيانات الطلب غير مكتملة.", {reason: parsed.reason});
    }
    const {requestId, organizationUIDs} = parsed.value;
    const callerUid = ctx.auth.uid;
    const db = admin.firestore();

    let reviewerName = parsed.value.reviewerName;
    if (!reviewerName) {
      const u = (await db.collection("users").doc(callerUid).get()).data() || {};
      reviewerName = String(u.fullName ?? u.name ?? u.displayName ?? "").trim().slice(0, 120);
    }

    return db.runTransaction(async (tx) => {
      const reqRef = db.collection("delegate_requests").doc(requestId);
      const reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) fail("request_not_found");
      const req = reqSnap.data() || {};
      const delegateId = boundDelegateId(requestId, req);
      const companyUID = typeof req.companyUID === "string" ? req.companyUID.trim() : "";
      if (!delegateId || !companyUID) fail("no_bound_delegate");

      const refs = organizationUIDs.map((org) => db
        .collection("organizations").doc(org)
        .collection("companies").doc(companyUID)
        .collection("delegates").doc(delegateId));
      const supUid = typeof req.supervisorUid === "string" ? req.supervisorUid.trim() : "";
      const needSup = organizationUIDs.some((o) => !orgAllowed(o, req, ""));
      const [docSnaps, supSnap] = await Promise.all([
        Promise.all(refs.map((r) => tx.get(r))),
        needSup && supUid ? tx.get(db.collection("users").doc(supUid)) : Promise.resolve(null),
      ]);
      const docs = docSnaps.map((s) => (s.exists ? (s.data() || {}) : null));

      if (alreadyApplied(requestId, req, docs)) {
        return {ok: true, alreadyApproved: true, activated: 0, flipped: 0};
      }
      const reqOk = checkRequest(role, callerUid, requestId, req);
      if (!reqOk.ok) fail(reqOk.reason);

      const supOrg = String(supSnap?.data()?.organizationUID ?? "").trim();
      const urls = requestUrlMap(req);
      const reviewedAt = new Date().toISOString();
      const updates: Array<[admin.firestore.DocumentReference, admin.firestore.UpdateData<admin.firestore.DocumentData>]> = [];
      let flipped = 0;
      for (let i = 0; i < refs.length; i++) {
        const org = organizationUIDs[i];
        if (!orgAllowed(org, req, supOrg)) fail("org_not_in_request", {organizationUID: org});
        const d = docs[i];
        if (!d) fail("delegate_not_found", {organizationUID: org});
        const plan = planActivation(org, companyUID, requestId, d, urls, reviewerName, reviewedAt);
        if (!plan.ok) fail(plan.reason, {organizationUID: org, documentKey: plan.documentKey ?? null});
        flipped += plan.flipped;
        updates.push([refs[i], {...plan.update, updatedAt: FieldValue.serverTimestamp()}]);
      }
      for (const [ref, u] of updates) tx.update(ref, u);
      tx.update(reqRef, {
        status: "approved",
        reviewedBy: reviewerName,
        reviewedAt,
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log("approveDelegateDocuments", {requestId, role, activated: updates.length, flipped});
      return {ok: true, alreadyApproved: false, activated: updates.length, flipped};
    });
  });
