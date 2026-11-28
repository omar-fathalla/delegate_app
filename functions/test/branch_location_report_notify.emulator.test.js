/**
 * Emulator test (TAS-397): a report's notifications are written once per
 * event (a retried event writes nothing new), go to the company's
 * supervisors (not HR, not a supervisor-delegate), then to the chain admin
 * (super admin when the chain has none) and the delegate, and the branch is
 * never touched. Fake data only.
 *
 *   npm run test:rules:tas397-branch-reports-notify
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

test("notifications per event, once; the branch stays as it was", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas397-notify"});
  const {notifyReport} = require("../lib/branch_location_report_notify");
  const db = admin.firestore();
  const users = {
    "tas397-sup": {role: "supervisor", companyUID: "tas397-co", organizationUID: "tas397-org"},
    "tas397-hr": {role: "hr", companyUID: "tas397-co", organizationUID: "tas397-org"},
    "tas397-sa": {role: "super-admin"},
    "tas397-orgadmin-b": {role: "organization-admin", organizationUID: "tas397-org-b"},
  };
  for (const [uid, u] of Object.entries(users)) await db.doc(`users/${uid}`).set({...u, fake: true});
  const branch = {branchName: "فرع تجريبي", organizationUID: "tas397-org", latitude: 30, longitude: 31, geofenceRadius: 100};
  await db.doc("branches/tas397-b1").set(branch);

  const open = {status: "open", delegateId: "tas397-d1", delegateName: "مندوب", branchId: "tas397-b1",
    branchName: "فرع تجريبي", companyUID: "tas397-co", organizationUID: "tas397-org", lat: 30.04, lng: 31.2};
  const forDoc = async (rid) => (await db.collection("notifications").where("reportId", "==", rid).get())
    .docs.map((d) => d.get("delegateUid")).sort();

  // Opened: the company supervisor only (HR is not a reviewer).
  assert.equal(await notifyReport(db, "tas397-d1_tas397-b1", "e1", undefined, open), 1);
  assert.equal(await notifyReport(db, "tas397-d1_tas397-b1", "e1", undefined, open), 0, "retry");
  assert.deepEqual(await forDoc("tas397-d1_tas397-b1"), ["tas397-sup"]);

  // Forwarded in a chain without an org admin: super admin + the delegate.
  const fwd = {...open, status: "forwarded"};
  assert.equal(await notifyReport(db, "tas397-d1_tas397-b1", "e2", open, fwd), 2);
  assert.deepEqual(await forDoc("tas397-d1_tas397-b1"), ["tas397-d1", "tas397-sa", "tas397-sup"]);

  // A chain with its own admin: the chain admin, not the super admin.
  const fwdB = {...fwd, organizationUID: "tas397-org-b", branchId: "tas397-b2", delegateId: "tas397-d2"};
  assert.equal(await notifyReport(db, "tas397-d2_tas397-b2", "e3", {...fwdB, status: "open"}, fwdB), 2);
  assert.deepEqual(await forDoc("tas397-d2_tas397-b2"), ["tas397-d2", "tas397-orgadmin-b"]);

  // Fixed: the delegate only.
  assert.equal(await notifyReport(db, "tas397-d1_tas397-b1", "e4", fwd, {...fwd, status: "fixed"}), 1);

  const b = (await db.doc("branches/tas397-b1").get()).data();
  assert.deepEqual({lat: b.latitude, lng: b.longitude, r: b.geofenceRadius}, {lat: 30, lng: 31, r: 100});
});
