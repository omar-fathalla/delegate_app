/**
 * Emulator test (TAS-363): offline check-in / check-out sent later through
 * delegateCheckIn / delegateCheckOut. Same key twice = one record; captured
 * time counts when trusted and inside the limits, otherwise arrival time;
 * always flagged for HR, never refused for its time.
 *
 *   npm run test:rules:tas363-offline-attendance
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

const ORG = "seed-fake-tas363-org";
const CO = "seed-fake-tas363-co";
const HOUR = 3600 * 1000;

test("offline records: idempotent, captured time limits, HR flag", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas363"});
  const {delegateCheckIn, delegateCheckOut} = require("../lib/attendance_callables");
  const db = admin.firestore();

  await db.doc(`organizations/${ORG}/branches/b1`)
    .set({name: "Fake Alpha", location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100});
  await db.doc(`organizations/${ORG}/branches/b2`)
    .set({name: "Fake Beta", location: {latitude: 30.06, longitude: 31.25}, geofenceRadius: 100});
  for (const d of ["d1", "d2", "d3", "d4"]) {
    await db.doc(`organizations/${ORG}/companies/${CO}/delegates/${d}`).set({status: "active"});
  }
  const ctx = (uid) => ({auth: {uid, token: {role: "delegate", delegateId: uid, orgId: ORG}}});
  const now = Date.now();
  const req = (extra = {}) => ({organizationId: ORG, companyId: CO, branchId: "b1", branchName: "Fake Alpha",
    lat: 30.0449, lng: 31.2357, offline: true, timeTrusted: true, syncedAtMs: now - 6 * HOUR, ...extra});
  const ms = (v) => v.toMillis();

  // 1. Trusted, 3 h ago: counts from the captured time; same key twice = one record.
  const captured = now - 3 * HOUR;
  const first = await delegateCheckIn.run(req({requestId: "tas363-off-1", capturedAtMs: captured}), ctx("d1"));
  assert.equal(first.ok, true);
  assert.equal(first.timeTrusted, true);
  const again = await delegateCheckIn.run(req({requestId: "tas363-off-1", capturedAtMs: captured}), ctx("d1"));
  assert.equal(again.already, true);
  const logs = await db.collection("attendance_logs").where("delegateId", "==", "d1").get();
  assert.equal(logs.size, 1);
  const rec = (await db.doc("attendance_logs/tas363-off-1").get()).data();
  assert.equal(ms(rec.timestamp), captured);
  assert.equal(rec.offlineCheckIn, true);
  assert.equal(rec.timeTrusted, true);
  assert.equal(ms(rec.capturedAt), captured);
  assert.ok(rec.receivedAt);

  // Offline check-out 1 h ago, linked to the offline check-in's id.
  const outAt = now - HOUR;
  const out = await delegateCheckOut.run({attendanceId: "tas363-off-1", lat: 30.0444, lng: 31.2357, offline: true,
    capturedAtMs: outAt, timeTrusted: true, syncedAtMs: now - 6 * HOUR}, ctx("d1"));
  assert.equal(out.ok, true);
  const closed = (await db.doc("attendance_logs/tas363-off-1").get()).data();
  assert.equal(ms(closed.checkOutTime), outAt);
  assert.equal(closed.offlineCheckOut, true);
  assert.equal(closed.checkOutTimeTrusted, true);
  const outDoc = (await db.doc("attendance_logs/tas363-off-1_out").get()).data();
  assert.equal(ms(outDoc.timestamp), outAt);
  assert.equal(outDoc.offlineCheckOut, true);
  // Retry of the same offline check-out: same answer.
  assert.equal((await delegateCheckOut.run({attendanceId: "tas363-off-1", lat: 30.0444, lng: 31.2357,
    offline: true, capturedAtMs: outAt, timeTrusted: true}, ctx("d1"))).already, true);

  // 2. Captured before the end of the last session (other branch): arrival time, flagged.
  const t0 = Date.now();
  const early = await delegateCheckIn.run(req({requestId: "tas363-off-2", branchId: "b2", branchName: "Fake Beta",
    lat: 30.06, lng: 31.25, capturedAtMs: now - 2 * HOUR}), ctx("d1"));
  assert.equal(early.timeTrusted, false);
  const earlyRec = (await db.doc("attendance_logs/tas363-off-2").get()).data();
  assert.equal(earlyRec.offlineTimeIssue, "before_last_session");
  assert.ok(ms(earlyRec.timestamp) >= t0 - 1000);

  // 3. In the future / older than 24 h / phone says untrusted: arrival time, flagged.
  const issueOf = async (uid, id, extra) => {
    const r = await delegateCheckIn.run(req({requestId: id, ...extra}), ctx(uid));
    assert.equal(r.ok, true);
    assert.equal(r.timeTrusted, false);
    const d = (await db.doc(`attendance_logs/${id}`).get()).data();
    assert.equal(d.offlineCheckIn, true);
    assert.equal(d.timeTrusted, false);
    return d.offlineTimeIssue;
  };
  assert.equal(await issueOf("d2", "tas363-off-3", {capturedAtMs: now + HOUR}), "in_future");
  await db.doc("attendance_logs/tas363-off-3").delete();
  assert.equal(await issueOf("d2", "tas363-off-4", {capturedAtMs: now - 30 * HOUR, syncedAtMs: now - 40 * HOUR}),
    "too_old");
  assert.equal(await issueOf("d3", "tas363-off-5", {timeTrusted: false, capturedAtMs: now - HOUR}),
    "device_untrusted");

  // 4. Outside the branch is still refused (distance re-checked at sync).
  await assert.rejects(
    delegateCheckIn.run(req({requestId: "tas363-off-6", lat: 30.0464, capturedAtMs: now - HOUR}), ctx("d4")),
    (e) => e.details && e.details.reason === "outside_branch");
});
