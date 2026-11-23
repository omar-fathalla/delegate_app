/**
 * TAS-258: per-device FCM tokens at fcm_tokens/{uid}/devices/{deviceId}.
 * Only the owner creates, updates, reads or deletes them; nobody reads another
 * user's devices (not even staff). The legacy fcm_tokens/{uid} rule is unchanged.
 * Fake data only.
 *
 * npm run test:rules:tas258
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails, assertDeniedByRule} = require("./_rules_testing");
const {collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc} = require("firebase/firestore");

const STAFF = {firebase: {sign_in_provider: "password"}};
const DELEGATE = {
  role: "delegate", delegateId: "del-1", delegateIds: ["del-1"],
  firebase: {sign_in_provider: "custom"},
};

const users = {
  "staff-1": {role: "supervisor", organizationUID: "seed-fake-org", companyUID: "seed-fake-co"},
  "staff-2": {role: "supervisor", organizationUID: "seed-fake-org", companyUID: "seed-fake-co"},
  "sa": {role: "super-admin"},
};

const device = (token, platform = "android") => ({token, platform, updatedAt: serverTimestamp()});

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas258",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    await setDoc(doc(db, "fcm_tokens/staff-2"), {token: "fake-legacy-2"});
    await setDoc(doc(db, "fcm_tokens/staff-2/devices/dev-x"), {token: "fake-2", platform: "ios"});
  });
});

after(async () => env && env.cleanup());

const as = (uid, token = STAFF) => env.authenticatedContext(uid, token).firestore();
const anon = () => env.authenticatedContext("anon", {firebase: {sign_in_provider: "anonymous"}}).firestore();

describe("owner manages own device docs", () => {
  test("staff user creates, refreshes, reads and deletes own device doc", async () => {
    const db = as("staff-1");
    const ref = doc(db, "fcm_tokens/staff-1/devices/dev-a");
    await assertSucceeds(setDoc(ref, device("fake-a")));
    await assertSucceeds(setDoc(ref, device("fake-a2")));
    await assertSucceeds(updateDoc(ref, {token: "fake-a3", updatedAt: serverTimestamp()}));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(getDocs(collection(db, "fcm_tokens/staff-1/devices")));
    await assertSucceeds(deleteDoc(ref));
  });

  test("delegate writes devices under its delegate id (custom token)", async () => {
    const db = as("del-1", DELEGATE);
    await assertSucceeds(setDoc(doc(db, "fcm_tokens/del-1/devices/dev-d"), device("fake-d", "ios")));
    await assertSucceeds(deleteDoc(doc(db, "fcm_tokens/del-1/devices/dev-d")));
  });

  test("legacy doc rule unchanged: owner writes, then deletes", async () => {
    const db = as("staff-1");
    await assertSucceeds(setDoc(doc(db, "fcm_tokens/staff-1"), {token: "fake-l", platform: "android", updatedAt: serverTimestamp()}));
    await assertSucceeds(getDoc(doc(db, "fcm_tokens/staff-1")));
    await assertSucceeds(deleteDoc(doc(db, "fcm_tokens/staff-1")));
  });
});

describe("nobody touches another user's devices", () => {
  test("cannot create a device doc under another uid", () =>
    assertDeniedByRule(setDoc(doc(as("staff-1"), "fcm_tokens/staff-2/devices/dev-evil"), device("fake-evil"))));
  test("cannot overwrite another user's device doc", () =>
    assertDeniedByRule(setDoc(doc(as("staff-1"), "fcm_tokens/staff-2/devices/dev-x"), device("fake-evil"))));
  test("cannot read another user's device doc", () =>
    assertDeniedByRule(getDoc(doc(as("staff-1"), "fcm_tokens/staff-2/devices/dev-x"))));
  test("cannot list another user's devices", () =>
    assertDeniedByRule(getDocs(collection(as("staff-1"), "fcm_tokens/staff-2/devices"))));
  test("super admin cannot read users' devices either", () =>
    assertDeniedByRule(getDoc(doc(as("sa"), "fcm_tokens/staff-2/devices/dev-x"))));
  test("cannot delete another user's device doc", () =>
    assertDeniedByRule(deleteDoc(doc(as("staff-1"), "fcm_tokens/staff-2/devices/dev-x"))));
  test("anonymous and signed-out users are denied", async () => {
    await assertFails(setDoc(doc(anon(), "fcm_tokens/anon/devices/d"), device("fake-anon")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "fcm_tokens/staff-2/devices/dev-x")));
  });
});

describe("device doc shape", () => {
  const ref = () => doc(as("staff-1"), "fcm_tokens/staff-1/devices/dev-shape");
  test("extra fields are rejected", () =>
    assertDeniedByRule(setDoc(ref(), {...device("fake-s"), uid: "staff-2"})));
  test("empty or non-string token is rejected", async () => {
    await assertDeniedByRule(setDoc(ref(), device("")));
    await assertDeniedByRule(setDoc(ref(), {token: 42, platform: "android"}));
  });
  test("unknown platform is rejected", () =>
    assertDeniedByRule(setDoc(ref(), device("fake-s", "windows"))));
  test("over-long device id is rejected", () =>
    assertDeniedByRule(setDoc(doc(as("staff-1"), `fcm_tokens/staff-1/devices/${"x".repeat(129)}`), device("fake-s"))));
  test("token only (no platform) is accepted", () =>
    assertSucceeds(setDoc(ref(), {token: "fake-s"})));
});
