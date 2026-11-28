/**
 * Emulator test (TAS-372): signed branch QR + App Check mark in delegateCheckIn,
 * and branchAttendanceQr (print / regenerate) against a real Firestore.
 *
 *   npm --prefix functions run build && bash scripts/emulators_exec.sh --only firestore \
 *     --project demo-tas372 "node --test functions/test/attendance_qr.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

const ORG = "seed-fake-tas372-org";
const CO = "seed-fake-tas372-co";

test("signed QR, regenerate makes the old print void, integrity marked", {skip: !live}, async () => {
  process.env.ATTENDANCE_QR_KEY = "emulator-only-key";
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas372"});
  const {delegateCheckIn, delegateCheckOut, branchAttendanceQr} = require("../lib/attendance_callables");
  const db = admin.firestore();

  await db.doc(`organizations/${ORG}/branches/b1`)
    .set({branchName: "Fake Alpha", location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100});
  await db.doc(`organizations/${ORG}/branches/b2`)
    .set({branchName: "Fake Beta", location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100});
  await db.doc(`organizations/${ORG}/companies/${CO}/delegates/d372`).set({status: "active"});

  const orgAdmin = {auth: {uid: "a1", token: {role: "organization-admin", orgId: ORG}}};
  const hr = {auth: {uid: "h1", token: {role: "hr", orgId: ORG, companyId: CO}}};
  const dctx = (app) => ({auth: {uid: "d372", token: {role: "delegate", delegateId: "d372", orgId: ORG}}, app});
  const req = (id, extra = {}) => ({organizationId: ORG, companyId: CO, branchId: "b1", requestId: id,
    lat: 30.0449, lng: 31.2357, branchName: "Fake Alpha", ...extra});
  const errOf = async (p) => {
    try {
      await p;
    } catch (e) {
      return (e.details && e.details.reason) || e.code;
    }
    return "accepted";
  };
  const checkOut = (id) => delegateCheckOut.run({attendanceId: id, lat: 30.0449, lng: 31.2357}, dctx());

  // Only the chain admin / global staff print it.
  assert.equal(await errOf(branchAttendanceQr.run({branchId: "b1", organizationUID: ORG}, hr)),
    "permission-denied");
  // No signed QR yet: null, and a legacy QR is accepted and marked.
  assert.deepEqual(await branchAttendanceQr.run({branchId: "b1", organizationUID: ORG}, orgAdmin),
    {qr: null, qrVersion: 0});
  await delegateCheckIn.run(req("tas372-legacy", {qr: {legacy: true}}), dctx({appId: "x"}));
  let rec = (await db.doc("attendance_logs/tas372-legacy").get()).data();
  assert.equal(rec.qrCheck, "legacy");
  assert.equal(rec.deviceIntegrity, "verified");
  await checkOut("tas372-legacy");

  // First signed QR (v1): the old print stops working for this branch.
  const v1 = await branchAttendanceQr.run({branchId: "b1", organizationUID: ORG, regenerate: true}, orgAdmin);
  assert.equal(v1.qrVersion, 1);
  assert.equal(v1.qr.branch, "Fake Alpha");
  assert.equal(await errOf(delegateCheckIn.run(req("tas372-legacy2", {branchId: "b1", qr: {legacy: true}}),
    dctx())), "qr_old");

  // Signed v1 on b2 (wrong branch) is invalid; on b1 accepted, no App Check = missing.
  assert.equal(await errOf(delegateCheckIn.run(req("tas372-wrong", {branchId: "b2", branchName: "Fake Beta",
    qr: v1.qr}), dctx())), "qr_invalid");
  // b1 already visited today, so use b2 with its own QR.
  const b2 = await branchAttendanceQr.run({branchId: "b2", organizationUID: ORG, regenerate: true}, orgAdmin);
  await delegateCheckIn.run(req("tas372-signed", {branchId: "b2", branchName: "Fake Beta", qr: b2.qr}), dctx());
  rec = (await db.doc("attendance_logs/tas372-signed").get()).data();
  assert.equal(rec.qrCheck, "signed");
  assert.equal(rec.qrVersion, 1);
  assert.equal(rec.deviceIntegrity, "missing");
  await checkOut("tas372-signed");

  // Regenerate b2: v1 print refused as old; replayed App Check token marked.
  const b2v2 = await branchAttendanceQr.run({branchId: "b2", organizationUID: ORG, regenerate: true}, orgAdmin);
  assert.equal(b2v2.qrVersion, 2);
  assert.equal((await db.doc(`organizations/${ORG}/branches/b2`).get()).data().qrVersion, 2);
  assert.equal(await errOf(delegateCheckIn.run(req("tas372-old", {branchId: "b2", branchName: "Fake Beta",
    qr: b2.qr}), dctx())), "qr_old");
  // Reading without regenerate returns the same current QR.
  const again = await branchAttendanceQr.run({branchId: "b2", organizationUID: ORG}, orgAdmin);
  assert.deepEqual(again.qr, b2v2.qr);
});
