/**
 * Emulator test (TAS-362): the hourly job against a real Firestore. Marks a
 * forgotten session on both paths, sends one notification, a second run
 * changes nothing, and a session closed meanwhile is left alone.
 *
 *   npm run test:rules:tas362-forgotten-job
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

test("marks forgotten sessions once, both paths", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas362-job"});
  const {markForgottenAttendanceRun} = require("../lib/attendance_forgotten");
  const db = admin.firestore();
  const H = 3600 * 1000;
  const now = Date.now();
  const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
  const base = {type: "check_in", delegateId: "d1", organizationId: "o1", companyId: "c1", branchName: "Fake Alpha"};

  await db.doc("attendance_logs/tas362-root").set({...base, timestamp: ts(now - 13 * H)});
  await db.doc("organizations/o1/attendance_logs/tas362-nested").set({...base, timestamp: ts(now - 20 * H)});
  await db.doc("attendance_logs/tas362-young").set({...base, timestamp: ts(now - 2 * H)});
  await db.doc("attendance_logs/tas362-closed").set({...base, timestamp: ts(now - 14 * H), checkOutTime: ts(now - 6 * H)});

  const r1 = await markForgottenAttendanceRun(db, now);
  assert.equal(r1.marked, 2);
  assert.equal((await db.doc("attendance_logs/tas362-root").get()).data().missingCheckOut, true);
  assert.equal((await db.doc("organizations/o1/attendance_logs/tas362-nested").get()).data().missingCheckOut, true);
  assert.equal((await db.doc("attendance_logs/tas362-root").get()).data().checkOutTime, undefined);
  assert.equal((await db.doc("attendance_logs/tas362-young").get()).data().missingCheckOut, undefined);
  assert.equal((await db.doc("attendance_logs/tas362-closed").get()).data().missingCheckOut, undefined);
  const n = (await db.doc("notifications/missing_checkout_tas362-root").get()).data();
  assert.equal(n.delegateUid, "d1");

  const r2 = await markForgottenAttendanceRun(db, now);
  assert.equal(r2.marked, 0, "a second run writes nothing");
  const notifs = await db.collection("notifications").where("attendanceId", "==", "tas362-root").get();
  assert.equal(notifs.size, 1);
});
