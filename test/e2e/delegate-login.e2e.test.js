/**
 * End-to-end delegate login on the emulators (auth + firestore), project
 * demo-tashil-e2e. The real delegateLoginV2 handler from functions/lib runs
 * in-process via its v1 callable .run() (the functions emulator's admin proxy
 * drops admin.firestore.FieldValue, an emulator-only artifact), against the
 * Auth and Firestore emulators. Proves P0 does not change delegate login:
 *   delegateLoginV2 (phone + national ID) -> signInWithCustomToken ->
 *   the real 1.14.3 collectionGroup('delegates').where(phoneNumber, whereIn, variants) query
 *   -> direct get of own doc. Fake data only.
 */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
// Same firebase-admin instance the function uses.
const admin = require("../../functions/node_modules/firebase-admin");
const {initializeApp, deleteApp} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInWithCustomToken, signInAnonymously, signOut} = require("firebase/auth");
const {getFirestore, connectFirestoreEmulator, collectionGroup, query, where, getDocs, doc, getDoc, updateDoc} = require("firebase/firestore");

const PROJECT = process.env.GCLOUD_PROJECT || "demo-tashil-e2e";
const PHONE = "01011112222";
const NID = "29001011234567";

// Verbatim port of 1.14.3 (abb1cb1) egyptianPhoneVariants.
function egyptianPhoneVariants(p) {
  const v = new Set([p]);
  if (p.startsWith("0") && p.length === 11) {
    const w = p.substring(1);
    v.add(w); v.add("20" + w); v.add("+20" + w); v.add("0020" + w); v.add("+2" + p); v.add("002" + p);
  }
  return [...v];
}

let app; let auth; let db; let fnExports;
before(async () => {
  // functions/lib/index.js calls admin.initializeApp() with the emulator env.
  fnExports = require("../../functions/lib/index.js");
  const fs = admin.firestore();
  await fs.doc("organizations/o1").set({name: "O1"});
  await fs.doc("organizations/o1/companies/c1").set({name: "C1"});
  await fs.doc("organizations/o1/companies/c1/delegates/e2e-del").set({
    phoneNumber: PHONE, nationalityID: NID, organizationUID: "o1", companyUID: "c1",
    status: "active", fullName: "E2E Fake Delegate",
  });
  await fs.doc("organizations/o1/companies/c1/delegates/e2e-other").set({
    phoneNumber: "01099990000", nationalityID: "29001019999999", organizationUID: "o1", companyUID: "c1", status: "active",
  });
  app = initializeApp({projectId: PROJECT, apiKey: "fake-api-key"}, "e2e");
  auth = getAuth(app);
  connectAuthEmulator(auth, "http://" + process.env.FIREBASE_AUTH_EMULATOR_HOST, {disableWarnings: true});
  db = getFirestore(app);
  const [h, p] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
  connectFirestoreEmulator(db, h, Number(p));
});
after(async () => {
  await signOut(auth).catch(() => {});
  await deleteApp(app);
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

async function callLogin(payload) {
  try {
    const result = await fnExports.delegateLoginV2.run(payload, {rawRequest: {ip: "127.0.0.1", headers: {}}});
    return {status: 200, body: {result}};
  } catch (e) {
    return {status: 400, body: {error: {status: e.code, reason: e.details && e.details.reason}}};
  }
}

test("anonymous client cannot read delegates (1.14.1 path is closed)", async () => {
  await signInAnonymously(auth);
  await assert.rejects(getDocs(query(collectionGroup(db, "delegates"), where("phoneNumber", "in", egyptianPhoneVariants(PHONE)))));
  await signOut(auth);
});

test("delegateLoginV2 -> custom token -> 1.14.3 self-read query and own doc get", async () => {
  const r = await callLogin({phone: PHONE, nationalId: NID, deviceId: "e2e-device-0001", deviceModel: "E2E"});
  assert.equal(r.status, 200, JSON.stringify(r.body).slice(0, 200));
  assert.ok(r.body.result && typeof r.body.result.token === "string");
  assert.deepEqual(r.body.result.delegateIds, ["e2e-del"]);
  const cred = await signInWithCustomToken(auth, r.body.result.token);
  const tok = await cred.user.getIdTokenResult();
  assert.equal(tok.claims.role, "delegate");

  const snap = await getDocs(query(collectionGroup(db, "delegates"), where("phoneNumber", "in", egyptianPhoneVariants(PHONE))));
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].id, "e2e-del");
  const own = await getDoc(doc(db, "organizations/o1/companies/c1/delegates/e2e-del"));
  assert.ok(own.exists());
  // Not someone else's, and not the login fields.
  await assert.rejects(getDocs(query(collectionGroup(db, "delegates"), where("phoneNumber", "in", ["01099990000"]))));
  await assert.rejects(updateDoc(doc(db, "organizations/o1/companies/c1/delegates/e2e-del"), {nationalityID: "1"}));
  await signOut(auth);
});

test("wrong national ID is refused by delegateLoginV2", async () => {
  const r = await callLogin({phone: "01099990000", nationalId: "29001010000000", deviceId: "e2e-device-0002"});
  assert.notEqual(r.status, 200);
});
