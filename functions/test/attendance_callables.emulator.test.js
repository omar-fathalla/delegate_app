/**
 * Emulator test (TAS-361 phase 2): delegateCheckIn / delegateCheckOut handlers
 * against a real Firestore (transaction, idempotency, refusals, check-out flag).
 *
 *   npm --prefix functions run build && bash scripts/emulators_exec.sh --only firestore \
 *     --project demo-tas361b "node --test functions/test/attendance_callables.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

const ORG = "seed-fake-tas361b-org";
const CO = "seed-fake-tas361b-co";

test("check-in, refusals, idempotent retry, check-out outside flagged", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas361b"});
  const {delegateCheckIn, delegateCheckOut} = require("../lib/attendance_callables");
  const db = admin.firestore();

  await db.doc(`organizations/${ORG}/branches/b1`)
    .set({name: "Fake Alpha", location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100});
  await db.doc(`organizations/${ORG}/branches/b2`)
    .set({name: "Fake Beta", location: {latitude: 30.06, longitude: 31.25}, geofenceRadius: 100});
  await db.doc(`organizations/${ORG}/companies/${CO}/delegates/d1`).set({status: "active"});

  const ctx = (uid = "d1", extra = {}) => ({auth: {uid, token: {role: "delegate", delegateId: uid, orgId: ORG, ...extra}}});
  const req = (extra = {}) => ({organizationId: ORG, companyId: CO, branchId: "b1", requestId: "tas361b-req-1",
    lat: 30.0449, lng: 31.2357, branchName: "Fake Alpha", delegateId: "attacker", ...extra});
  const reasonOf = async (p) => {
    try {
      await p;
    } catch (e) {
      return e.details && e.details.reason;
    }
    return "accepted";
  };

  // Outside the branch: refused, nothing written.
  assert.equal(await reasonOf(delegateCheckIn.run(req({lat: 30.0464, requestId: "tas361b-far"}), ctx())),
    "outside_branch");
  assert.equal((await db.doc("attendance_logs/tas361b-far").get()).exists, false);
  // Not a member of the company / not a delegate token.
  assert.equal(await reasonOf(delegateCheckIn.run(req({requestId: "tas361b-x1"}), ctx("d9"))), "not_member");
  assert.equal(await reasonOf(delegateCheckIn.run(req({requestId: "tas361b-x2"}),
    {auth: {uid: "s1", token: {role: "hr", orgId: ORG}}})), "not_delegate");

  // Accepted; identity from the token, not from data.delegateId.
  const ok = await delegateCheckIn.run(req(), ctx());
  assert.equal(ok.ok, true);
  assert.equal(ok.attendanceId, "tas361b-req-1");
  const rec = (await db.doc("attendance_logs/tas361b-req-1").get()).data();
  assert.equal(rec.delegateId, "d1");
  assert.equal(rec.source, "server");
  assert.ok(rec.timestamp);

  // Retry after a timeout: same record, no second one.
  const again = await delegateCheckIn.run(req(), ctx());
  assert.equal(again.already, true);
  // A new check-in while the session is open (other branch) is refused.
  assert.equal(await reasonOf(delegateCheckIn.run(req({branchId: "b2", requestId: "tas361b-req-2",
    lat: 30.06, lng: 31.25}), ctx())), "open_session_other_branch");

  // Someone else cannot close it.
  assert.equal(await reasonOf(delegateCheckOut.run({attendanceId: "tas361b-req-1", lat: 30.0444, lng: 31.2357},
    ctx("d2"))), "not_owner");

  // Check-out ~1.1 km away: written and flagged, not refused.
  const out = await delegateCheckOut.run({attendanceId: "tas361b-req-1", lat: 30.0544, lng: 31.2357}, ctx());
  assert.equal(out.ok, true);
  assert.equal(out.outsideBranch, true);
  const closed = (await db.doc("attendance_logs/tas361b-req-1").get()).data();
  assert.equal(closed.checkOutDocId, "tas361b-req-1_out");
  assert.ok(closed.checkOutTime);
  assert.equal((await db.doc("attendance_logs/tas361b-req-1_out").get()).data().type, "check_out");
  // Retry of the same check-out: same answer, no error.
  assert.equal((await delegateCheckOut.run({attendanceId: "tas361b-req-1", lat: 30.0544, lng: 31.2357}, ctx())).already,
    true);

  // Same branch again today: refused.
  assert.equal(await reasonOf(delegateCheckIn.run(req({requestId: "tas361b-req-3"}), ctx())), "same_branch_today");
  // Another branch after closing: accepted.
  const beta = await delegateCheckIn.run(req({branchId: "b2", requestId: "tas361b-req-4", lat: 30.06, lng: 31.25,
    branchName: "Fake Beta"}), ctx());
  assert.equal(beta.ok, true);
});
