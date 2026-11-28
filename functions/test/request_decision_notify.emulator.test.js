/**
 * Emulator test (TAS-371): a decision is announced once (a retried event
 * writes nothing new), and an old staff app's change (no marker) is not.
 *
 *   npm run test:rules:tas371-decisions
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

test("one notification per decision, none without the marker", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas371"});
  const {notifyDecision} = require("../lib/request_decision_notify");
  const db = admin.firestore();
  const pending = {status: "pending", delegateUid: "d1", organizationUID: "o1", companyUID: "c1"};
  const approved = {...pending, status: "approved", notifyByServer: true, resolvedByName: "HR"};

  assert.equal(await notifyDecision(db, "leave", "tas371-l1", pending, approved), true);
  assert.equal(await notifyDecision(db, "leave", "tas371-l1", pending, approved), false, "retry");
  const n = await db.collection("notifications").where("requestId", "==", "tas371-l1").get();
  assert.equal(n.size, 1);
  assert.equal(n.docs[0].id, "leave_tas371-l1_approved");

  const old = {...pending, status: "rejected"};
  assert.equal(await notifyDecision(db, "unbind", "tas371-u1", pending, old), false);
  assert.equal((await db.doc("notifications/unbind_tas371-u1_rejected").get()).exists, false);
});
