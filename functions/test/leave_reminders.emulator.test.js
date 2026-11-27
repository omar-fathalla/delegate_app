/**
 * Emulator test (TAS-370, L-4): the hourly reminder job against a real
 * Firestore. Reminds an old pending request once (supervisors + HR), skips
 * young, approved and other-company HR, and a second run sends nothing.
 *
 *   npm run test:rules:tas370-leave-reminders
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

test("reminds overdue pending leaves once", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas370-reminders"});
  const {remindPendingLeavesRun} = require("../lib/leave_reminders");
  const db = admin.firestore();
  const H = 3600 * 1000;
  const now = Date.now();
  const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
  const base = {companyUID: "c1", organizationUID: "o1", delegateUid: "d1", delegateName: "Fake One", type: "annual"};

  await db.doc("users/hr-c1").set({role: "hr", companyUID: "c1"});
  await db.doc("users/hr-c1-off").set({role: "hr", companyUID: "c1", status: "suspended"});
  await db.doc("users/hr-c2").set({role: "hr", companyUID: "c2"});
  await db.doc("leave_requests/tas370-old").set({...base, status: "pending", createdAt: ts(now - 30 * H)});
  await db.doc("leave_requests/tas370-young").set({...base, status: "pending", createdAt: ts(now - 2 * H)});
  await db.doc("leave_requests/tas370-done").set({...base, status: "approved", createdAt: ts(now - 50 * H)});

  const r1 = await remindPendingLeavesRun(db, now);
  assert.equal(r1.sent, 2, "supervisor broadcast + the one active HR of c1");
  assert.equal((await db.doc("notifications/leave_reminder_tas370-old").get()).data().delegateUid, "supervisor_c1");
  assert.equal((await db.doc("notifications/leave_reminder_tas370-old_hr-c1").get()).exists, true);
  assert.equal((await db.doc("notifications/leave_reminder_tas370-old_hr-c2").get()).exists, false);
  assert.equal((await db.doc("notifications/leave_reminder_tas370-young").get()).exists, false);
  assert.equal((await db.doc("notifications/leave_reminder_tas370-done").get()).exists, false);

  const r2 = await remindPendingLeavesRun(db, now + H);
  assert.equal(r2.sent, 0, "a second run sends nothing");
});
