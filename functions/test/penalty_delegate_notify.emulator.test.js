/**
 * Emulator test (TAS-365): the delegate's penalty notification is written
 * once (a retried event writes nothing new), a PENDING penalty writes
 * nothing, and an old staff app's own notification is not doubled.
 *
 *   npm run test:rules:tas365-penalty-notify
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

test("one delegate notification per penalty event", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas365"});
  const {notifyPenaltyChange} = require("../lib/penalty_delegate_notify");
  const db = admin.firestore();
  const ts = admin.firestore.Timestamp.fromMillis(Date.now());
  const base = {title: "تأخير", fineAmount: 100, targetDelegateId: "tas365-d1", organizationId: "tas365-o1",
    companyId: "tas365-c1", createdByName: "Fake Supervisor"};
  const marked = (status) => ({...base, status, updatedAt: ts, notifyByServerAt: ts});
  const opts = {eventMs: Date.now(), waitMs: 0};
  const count = async (id) => (await db.collection("notifications").where("penaltyId", "==", id).get()).size;

  // Created PENDING: nothing for the delegate.
  await notifyPenaltyChange(db, "tas365-p0", null, {...base, status: "PENDING_BRANCHES_MARKETING"}, opts);
  assert.equal(await count("tas365-p0"), 0);

  // Created ISSUED (supervisor penalty): one, and a retry writes nothing.
  assert.equal((await notifyPenaltyChange(db, "tas365-p1", null, marked("ISSUED"), opts)).delegate, true);
  assert.equal((await notifyPenaltyChange(db, "tas365-p1", null, marked("ISSUED"), opts)).delegate, false);
  assert.equal(await count("tas365-p1"), 1);
  assert.equal((await db.doc("notifications/penalty_tas365-p1_del_issued").get()).get("delegateUid"), "tas365-d1");

  // Update to ISSUED by a new app: one.
  const pending = {...base, status: "PENDING_GENERAL_MANAGER"};
  await notifyPenaltyChange(db, "tas365-p2", pending, marked("ISSUED"), opts);
  assert.equal(await count("tas365-p2"), 1);

  // Old app: it wrote its own notification for the delegate, the server does not add one.
  await db.collection("notifications").add({penaltyId: "tas365-p3", delegateUid: "tas365-d1", type: "penalty",
    title: "اعتماد وصدور غرامة رسمية", createdAt: admin.firestore.FieldValue.serverTimestamp()});
  const res = await notifyPenaltyChange(db, "tas365-p3", pending, {...base, status: "ISSUED", updatedAt: ts}, opts);
  assert.equal(res.delegate, false);
  assert.equal(await count("tas365-p3"), 1);

  // Old app whose write failed: the server still notifies.
  const res4 = await notifyPenaltyChange(db, "tas365-p4", pending, {...base, status: "ISSUED", updatedAt: ts}, opts);
  assert.equal(res4.delegate, true);

  // Dispute opened: the chain admin (named) and the super-admin broadcast.
  await db.doc("users/tas365-admin").set({role: "organizationAdmin", organizationUID: "tas365-o1"});
  const d = await notifyPenaltyChange(db, "tas365-p5", marked("ISSUED"),
    {...base, status: "DISPUTED", disputeReason: "غلط"}, opts);
  assert.equal(d.deciders, 2);
  assert.equal((await db.doc("notifications/penalty_tas365-p5_disp_tas365-admin").get()).exists, true);
  assert.equal((await db.doc("notifications/penalty_tas365-p5_disp_super").get()).get("delegateUid"), "super-admin");
});
