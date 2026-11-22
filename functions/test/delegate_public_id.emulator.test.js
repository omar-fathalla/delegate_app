/**
 * Emulator test (TAS-246): one delegatePublicId per delegate.
 *
 *   bash scripts/emulators_exec.sh --only firestore --project demo-tas246 \
 *     "node --test functions/test/delegate_public_id.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

test("several chains, several codes -> oldest everywhere; no code -> one new code", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas246"});
  const {enforceSinglePublicId} = require("../lib/delegate_public_id");
  const db = admin.firestore();
  const p = (org, uid) => `organizations/${org}/companies/CO/delegates/${uid}`;
  const base = {companyUID: "CO", fullName: "تجربة", status: "active"};
  await db.doc(p("A", "u1")).set({...base, uid: "u1", delegatePublicId: "DEL-6389"});
  await db.doc(p("B", "u1")).set({...base, uid: "u1", delegatePublicId: "DEL-6595"});
  await db.doc(p("C", "u1")).set({...base, uid: "u1"});
  await db.doc(p("F", "u1")).set({boundDeviceId: "dev"}); // device stub, never touched
  await db.doc("users/u1").set({role: "delegate", delegatePublicId: "DEL-6595"});

  const r1 = await enforceSinglePublicId(db, "u1");
  assert.deepEqual(r1, {code: "DEL-6389", written: 3});
  for (const path of [p("A", "u1"), p("B", "u1"), p("C", "u1"), "users/u1"]) {
    assert.equal((await db.doc(path).get()).data().delegatePublicId, "DEL-6389", path);
  }
  assert.equal((await db.doc(p("F", "u1")).get()).data().delegatePublicId, undefined);
  assert.deepEqual(await enforceSinglePublicId(db, "u1"), {code: "DEL-6389", written: 0});

  await db.doc("counters/delegates").set({count: 6897});
  await db.doc(p("A", "u2")).set({...base, uid: "u2"});
  await db.doc(p("B", "u2")).set({...base, uid: "u2"});
  await db.doc(p("A", "u3")).set({...base, uid: "u3", status: "pending"});
  assert.deepEqual(await enforceSinglePublicId(db, "u2"), {code: "DEL-6898", written: 2});
  assert.equal((await db.doc(p("B", "u2")).get()).data().delegatePublicId, "DEL-6898");
  assert.deepEqual(await enforceSinglePublicId(db, "u3"), {code: "", written: 0});
  assert.equal((await db.doc("counters/delegates").get()).data().count, 6898);
});
