/**
 * Ghost guard (18 Nov 2026): a delegate link doc may be updated by the app,
 * but never created without an identity (name / national ID / phone).
 * Old builds (1.11) wrote only the bound device with set(merge: true), which
 * re-created deleted delegates as nameless docs (77 on prod).
 *
 * Runs against BOTH the strict repo rules and the interim prod ruleset.
 * Emulator only: npm run test:rules:ghost
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");

const read = (p) => readFileSync(resolve(__dirname, p), "utf8");
const LIVE = "organizations/o1/companies/c1/delegates/d1";
const GONE = "organizations/o1/companies/c1/delegates/gone1";
// Exactly what device_binding_service (1.11) wrote.
const DEVICE = {
  boundDeviceId: "RP1A.200720.011", boundDeviceModel: "OPPO CPH1989", boundDeviceBrand: "OPPO",
  boundDeviceOs: "Android 11 (SDK 30)", deviceBoundAt: new Date(), deviceLastSeenAt: new Date(),
  isDeviceLocked: true,
};
const BASE = {
  uid: "d1", fullName: "Real Delegate", organizationUID: "o1", companyUID: "c1",
  status: "active", phoneNumber: "01011111111", nationalityID: "30302141801253",
};

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("users/sa").set({role: "super-admin"});
    await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
    await db.doc("users/ca").set({role: "company-admin", organizationUID: "o1", companyUID: "c1"});
    await db.doc("organizations/o1").set({name: "Org"});
    await db.doc("organizations/o1/companies/c1").set({name: "Co"});
    await db.doc(LIVE).set(BASE);
  });
}

describe("interim prod rules: no ghost delegate creates", () => {
  let env;
  const anon = () => env.authenticatedContext("anon-1", {firebase: {sign_in_provider: "anonymous"}}).firestore();
  const staff = (uid) => env.authenticatedContext(uid).firestore();
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-ghost-interim",
      firestore: {rules: read("../../firestore/interim-prod-hardening.rules")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => seed(env));

  test("old app device write on a deleted delegate (set merge = create) is denied", async () => {
    await assertFails(anon().doc(GONE).set(DEVICE, {merge: true}));
    await assertFails(anon().doc(GONE).set({...DEVICE, position: "Promoter", delegatePublicId: "DEL-1"}, {merge: true}));
  });

  test("old app device write on a live delegate (update) still works", async () => {
    await assertSucceeds(anon().doc(LIVE).set(DEVICE, {merge: true}));
    await assertSucceeds(anon().doc(LIVE).update({deviceLastSeenAt: new Date()}));
  });

  test("a staff account on the old app cannot create a ghost under its own uid", async () => {
    await assertFails(staff("ca").doc("organizations/o1/companies/c1/delegates/ca").set(DEVICE, {merge: true}));
  });

  test("staff create with identity keeps working (HR web / approvals)", async () => {
    await assertSucceeds(staff("ca").doc("organizations/o1/companies/c1/delegates/new1").set({...BASE, uid: "new1"}));
    await assertSucceeds(staff("sa").doc("organizations/o1/companies/c1/delegates/new2").set({
      uid: "new2", phoneNumber: "01022222222", organizationUID: "o1", companyUID: "c1", status: "pending",
    }));
  });

  test("staff create with whitespace-only name and no phone/national ID is denied", async () => {
    await assertFails(staff("sa").doc("organizations/o1/companies/c1/delegates/new3").set({
      ...DEVICE, fullName: "",
    }));
  });

  test("delete and read are unchanged", async () => {
    await assertSucceeds(anon().doc(LIVE).get());
    await assertSucceeds(staff("ca").doc(LIVE).delete());
  });
});

describe("strict repo rules: a delegate never creates a link doc", () => {
  let env;
  const CLAIMS = {
    sa: {role: "super-admin"},
    sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
    d1: {role: "delegate", delegateId: "d1", organizationUID: "o1", companyUID: "c1", companyId: "c1", orgId: "o1"},
    gone1: {role: "delegate", delegateId: "gone1", companyId: "c1", orgId: "o1"},
  };
  const as = (uid) => env.authenticatedContext(uid, {
    firebase: {sign_in_provider: "custom"}, ...(CLAIMS[uid] || {}),
  }).firestore();
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-ghost-strict",
      firestore: {rules: read("../../firestore.rules")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => seed(env));

  test("deleted delegate with a still-valid token cannot re-create its doc", async () => {
    await assertFails(as("gone1").doc(GONE).set({updatedAt: "t"}, {merge: true}));
    await assertFails(as("gone1").doc(GONE).set({
      fullName: "x", phoneNumber: "010", organizationUID: "o1", companyUID: "c1", status: "pending",
    }));
  });

  test("device fields on create are denied for everyone", async () => {
    await assertFails(as("sa").doc("organizations/o1/companies/c1/delegates/n1").set({...BASE, uid: "n1", ...DEVICE}));
  });

  test("delegate self-update of allow-listed fields still works", async () => {
    await assertSucceeds(as("d1").doc(LIVE).update({updatedAt: "t-self"}));
  });

  test("staff create without identity is denied; with identity is allowed", async () => {
    await assertFails(as("sa").doc("organizations/o1/companies/c1/delegates/n2").set({
      uid: "n2", organizationUID: "o1", companyUID: "c1", status: "pending",
    }));
    await assertSucceeds(as("sa").doc("organizations/o1/companies/c1/delegates/n3").set({...BASE, uid: "n3"}));
    await assertSucceeds(as("sup").doc("organizations/o1/companies/c1/delegates/n4").set({
      organizationUID: "o1", companyUID: "c1", status: "pending", phoneNumber: "01088888888",
    }));
  });
});
