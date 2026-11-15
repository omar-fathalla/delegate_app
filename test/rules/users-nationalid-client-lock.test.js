/**
 * TA-32 users/{uid}: clients cannot write nationalId / nationalityID.
 * Changes go through update_national_id request flow (Admin SDK).
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, updateDoc, setDoc} = require("firebase/firestore");

const USERS = {
  sa: {role: "super-admin", organizationUID: "o1"},
  ts: {role: "technical_support", organizationUID: "o1"},
  org: {role: "organization-admin", organizationUID: "o1"},
  adm: {role: "admin", organizationUID: "o1", companyUID: "c1"},
  sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
  hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
  d1: {
    role: "delegate",
    organizationUID: "o1",
    companyUID: "c1",
    uid: "d1",
    nationalId: "29901010101011",
    nationalityID: "29901010101011",
  },
};

const PATCH = {nationalId: "28801010101000", nationalityID: "28801010101000", updatedAt: "t"};
const PATCH_ALT = {nationalityID: "27701010101011", updatedAt: "t"};

describe("users/{uid} nationalId client lock (TA-32)", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-users-nationalid-lock",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [id, d] of Object.entries(USERS)) await db.doc(`users/${id}`).set(d);
      await db.doc("organizations/o1").set({name: "O1"});
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
    });
  });

  test("super-admin and tech cannot client-update nationalId on users docs", async () => {
    await assertFails(updateDoc(doc(as("sa"), "users/d1"), PATCH));
    await assertFails(updateDoc(doc(as("ts"), "users/d1"), PATCH));
    await assertFails(updateDoc(doc(as("sa"), "users/hr"), PATCH_ALT));
  });

  test("company and org staff cannot client-update nationalId on users docs", async () => {
    for (const u of ["sup", "adm", "org", "hr"]) {
      await assertFails(updateDoc(doc(as(u), "users/d1"), PATCH));
    }
  });

  test("delegate self cannot client-update nationalId on own users doc", async () => {
    await assertFails(updateDoc(doc(as("d1"), "users/d1"), PATCH));
  });

  test("staff may still update non-identity fields on users docs", async () => {
    await assertSucceeds(updateDoc(doc(as("sup"), "users/d1"), {displayName: "x", updatedAt: "t"}));
    await assertSucceeds(updateDoc(doc(as("sa"), "users/hr"), {displayName: "y", updatedAt: "t"}));
  });

  test("clients cannot create users docs carrying nationalId", async () => {
    await assertFails(setDoc(doc(as("sa"), "users/new-del"), {
      role: "delegate",
      organizationUID: "o1",
      companyUID: "c1",
      nationalId: "29901010101011",
      nationalityID: "29901010101011",
    }));
    await assertFails(setDoc(doc(as("sup"), "users/new2"), {
      role: "delegate",
      organizationUID: "o1",
      companyUID: "c1",
      uid: "new2",
      nationalId: "29901010101011",
    }));
    await assertSucceeds(setDoc(doc(as("sup"), "users/new3"), {
      role: "delegate",
      organizationUID: "o1",
      companyUID: "c1",
      uid: "new3",
    }));
  });
});