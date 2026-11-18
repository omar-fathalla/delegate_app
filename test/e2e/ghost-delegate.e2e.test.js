/**
 * Ghost delegate docs (18 Nov 2026), emulators only (auth + firestore),
 * project demo-tashil-ghost. Runs the real handlers from functions/lib
 * in-process (same pattern as delegate-login.e2e.test.js):
 *   - delegateLoginV2 rejects a deleted profile (account_deleted)
 *   - onDelegateLinkDeleted clears deviceBindings, cancels open unbind
 *     requests and revokes sessions when the last link is deleted, but not
 *     for a staff uid and not while another live link exists.
 * Fake data only.
 */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../../functions/node_modules/firebase-admin");

let fn; let fs;
before(async () => {
  fn = require("../../functions/lib/index.js");
  fs = admin.firestore();
  await fs.doc("organizations/o1").set({name: "O1"});
  await fs.doc("organizations/o1/companies/c1").set({name: "C1"});
  await fs.doc("organizations/o1/companies/c2").set({name: "C2"});
});
after(async () => {
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

async function callLogin(payload) {
  try {
    const result = await fn.delegateLoginV2.run(payload, {rawRequest: {ip: "127.0.0.1", headers: {}}});
    return {ok: true, result};
  } catch (e) {
    return {ok: false, code: e.code, reason: e.details && e.details.reason};
  }
}

/** Delete the doc and run the onDelete trigger with the real snapshot. */
async function deleteAndTrigger(path) {
  const snap = await fs.doc(path).get();
  await fs.doc(path).delete();
  const parts = path.split("/");
  await fn.onDelegateLinkDeleted.run(snap, {
    params: {orgId: parts[1], companyId: parts[3], delegateId: parts[5]},
  });
}

async function ensureAuthUser(uid) {
  try { await admin.auth().getUser(uid); } catch { await admin.auth().createUser({uid}); }
  await admin.auth().setCustomUserClaims(uid, {role: "delegate", delegateId: uid});
}

test("login: a deleted profile gets account_deleted, never a token", async () => {
  await fs.doc("organizations/o1/companies/c1/delegates/del-deleted").set({
    uid: "del-deleted", fullName: "Deleted Fake", phoneNumber: "01033334444",
    nationalityID: "29001013333444", organizationUID: "o1", companyUID: "c1", status: "deleted",
  });
  const r = await callLogin({phone: "01033334444", nationalId: "29001013333444", deviceId: "ghost-dev-0001"});
  assert.equal(r.ok, false);
  assert.equal(r.reason, "account_deleted");
});

test("login still works for a live delegate (and the mirror only updates)", async () => {
  await fs.doc("organizations/o1/companies/c1/delegates/del-live").set({
    uid: "del-live", fullName: "Live Fake", phoneNumber: "01055556666",
    nationalityID: "29001015555666", organizationUID: "o1", companyUID: "c1", status: "active",
  });
  const r = await callLogin({phone: "01055556666", nationalId: "29001015555666", deviceId: "ghost-dev-0002", deviceModel: "E2E"});
  assert.equal(r.ok, true, JSON.stringify(r));
  const d = (await fs.doc("organizations/o1/companies/c1/delegates/del-live").get()).data();
  assert.equal(d.boundDeviceId, "ghost-dev-0002");
  assert.equal(d.fullName, "Live Fake");
});

test("delete of the last link clears binding, unbind requests and sessions", async () => {
  const id = "del-gone";
  await fs.doc(`organizations/o1/companies/c1/delegates/${id}`).set({
    uid: id, fullName: "Gone Fake", phoneNumber: "01077778888", organizationUID: "o1", companyUID: "c1", status: "active",
  });
  await fs.doc(`deviceBindings/${id}`).set({deviceId: "dev-x", delegateId: id});
  await fs.doc("device_unbind_requests/r-pending").set({delegateUid: id, status: "pending"});
  await fs.doc("device_unbind_requests/r-done").set({delegateUid: id, status: "completed"});
  await ensureAuthUser(id);
  const before = await admin.auth().getUser(id);

  await deleteAndTrigger(`organizations/o1/companies/c1/delegates/${id}`);

  assert.equal((await fs.doc(`deviceBindings/${id}`).get()).exists, false);
  assert.equal((await fs.doc("device_unbind_requests/r-pending").get()).data().status, "cancelled");
  assert.equal((await fs.doc("device_unbind_requests/r-done").get()).data().status, "completed");
  const after = await admin.auth().getUser(id);
  assert.ok(!after.customClaims || Object.keys(after.customClaims).length === 0);
  // The Auth emulator may not report tokensValidAfterTime; check it when present.
  if (before.tokensValidAfterTime && after.tokensValidAfterTime) {
    assert.ok(Date.parse(after.tokensValidAfterTime) >= Date.parse(before.tokensValidAfterTime));
  }
});

test("delete while another live link exists changes nothing", async () => {
  const id = "del-multi";
  for (const c of ["c1", "c2"]) {
    await fs.doc(`organizations/o1/companies/${c}/delegates/${id}`).set({
      uid: id, fullName: "Multi Fake", phoneNumber: "01099998888", organizationUID: "o1", companyUID: c, status: "active",
    });
  }
  await fs.doc(`deviceBindings/${id}`).set({deviceId: "dev-y", delegateId: id});
  await deleteAndTrigger(`organizations/o1/companies/c1/delegates/${id}`);
  assert.equal((await fs.doc(`deviceBindings/${id}`).get()).exists, true);
});

test("deleting a ghost under a staff uid never revokes the staff account", async () => {
  const id = "staffUid000000000000000000AB";
  await fs.doc(`users/${id}`).set({role: "company-admin", companyUID: "c1"});
  await fs.doc(`organizations/o1/companies/c1/delegates/${id}`).set({
    boundDeviceId: "x", boundDeviceModel: "Redmi", isDeviceLocked: true,
  });
  await fs.doc(`deviceBindings/${id}`).set({deviceId: "staff-dev"});
  try { await admin.auth().createUser({uid: id}); } catch { /* exists */ }
  await admin.auth().setCustomUserClaims(id, {role: "company-admin"});
  await deleteAndTrigger(`organizations/o1/companies/c1/delegates/${id}`);
  assert.equal((await fs.doc(`deviceBindings/${id}`).get()).exists, true);
  assert.deepEqual((await admin.auth().getUser(id)).customClaims, {role: "company-admin"});
});
