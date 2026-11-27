/**
 * Emulator test (TAS-361 phase 1): the attendance trigger body against a real
 * Firestore. Branch lookup (nested then root), the transaction write, and the
 * loop guard (re-running on the trigger's own write changes nothing).
 *
 *   npm --prefix functions run build && bash scripts/emulators_exec.sh --only firestore \
 *     --project demo-tas361 "node --test functions/test/attendance_verify.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

const ORG = "seed-fake-tas361-org";

test("check-in, outside check-out, loop guard, root branch fallback", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas361"});
  const {applyAttendanceVerification} = require("../lib/attendance_verify");
  const db = admin.firestore();

  await db.doc(`organizations/${ORG}/branches/b1`)
    .set({name: "fake", location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100});
  await db.doc("branches/root-b2").set({name: "fake root", latitude: 30.05, longitude: 31.24});

  const ref = db.doc("attendance_logs/tas361-a1");
  const checkIn = {type: "check_in", delegateId: "d1", organizationId: ORG, branchId: "b1",
    branchOrganizationUID: ORG, location: {latitude: 30.0449, longitude: 31.2357}};
  await ref.set(checkIn);
  const w1 = await applyAttendanceVerification(db, ref, null, checkIn);
  assert.equal(w1.verifiedInsideBranch, true);
  let doc = (await ref.get()).data();
  assert.equal(doc.verifiedInsideBranch, true);
  assert.ok(doc.verifiedAt, "server timestamp written");

  // The trigger's own write fires the trigger again: nothing to do.
  assert.equal(await applyAttendanceVerification(db, ref, checkIn, doc), null);

  // Check-out ~222 m away: flagged, not rejected.
  await ref.update({checkOutTime: admin.firestore.FieldValue.serverTimestamp(),
    checkOutLocation: {latitude: 30.0464, longitude: 31.2357}});
  const afterOut = (await ref.get()).data();
  const w2 = await applyAttendanceVerification(db, ref, doc, afterOut);
  assert.equal(w2.checkOutOutsideBranch, true);
  doc = (await ref.get()).data();
  assert.equal(doc.checkOutOutsideBranch, true);
  assert.ok(doc.checkOutVerifiedDistanceMeters > 200);
  assert.equal(await applyAttendanceVerification(db, ref, afterOut, doc), null);

  // Branch only in root branches/ (no nested doc for this id).
  const ref2 = db.doc(`organizations/${ORG}/attendance_logs/tas361-a2`);
  const rootIn = {type: "check_in", delegateId: "d1", organizationId: ORG, branchId: "root-b2",
    location: {latitude: 30.05, longitude: 31.24}};
  await ref2.set(rootIn);
  const w3 = await applyAttendanceVerification(db, ref2, null, rootIn);
  assert.equal(w3.verifiedReason, "ok");
  assert.equal(w3.verifiedInsideBranch, true);
});
