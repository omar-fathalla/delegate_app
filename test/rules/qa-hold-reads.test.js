/**
 * QA HOLD fixes at e3c8cf6: supervisor reads, any-chain company access,
 * photo_permissions list budget, and field-edit policy.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("./_rules_testing");
const {doc, setDoc, updateDoc, getDoc, collection, getDocs, collectionGroup, query, where} = require("firebase/firestore");

const PROJECT_ID = "demo-qa-hold-reads";
const USERS = {
  sa: {role: "super-admin", organizationUID: "o1"},
  ts: {role: "technical_support", organizationUID: "o1"},
  org: {role: "organization-admin", organizationUID: "o1"},
  mkt: {role: "marketing", organizationUID: "o1"},
  adm: {role: "admin", organizationUID: "o1", companyUID: "c1"},
  sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
  hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
  acc: {role: "accountant", organizationUID: "o1", companyUID: "c1"},
  br: {role: "branches_marketing_manager", organizationUID: "o1", companyUID: "c1"},
  sup2: {role: "supervisor", organizationUID: "o3", companyUID: "c2"},
  d1: {role: "delegate", organizationUID: "o1", companyUID: "c1"},
};

function delegateDoc(overrides = {}) {
  return {
    uid: "d1", organizationUID: "o1", companyUID: "c1", status: "active",
    fullName: "مندوب تجريبي", phoneNumber: "01000000011",
    nationalId: "29901010101011", nationalityID: "29901010101011",
    profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
    documents: [],
    ...overrides,
  };
}

describe("qa hold supervisor reads and edit policy", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [id, d] of Object.entries(USERS)) await db.doc(`users/${id}`).set(d);
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc("organizations/o2/companies/c1").set({name: "C1 in o2"});
      await db.doc("organizations/o3/companies/c2").set({name: "C2"});
      await db.doc("organizations/o1/companies/c1/delegates/d1").set(delegateDoc());
      await db.doc("organizations/o2/companies/c1/delegates/d1").set(delegateDoc({organizationUID: "o2"}));
      await db.doc("organizations/o3/companies/c2/delegates/dx").set(delegateDoc({
        uid: "dx", organizationUID: "o3", companyUID: "c2", fullName: "آخر",
      }));
      await db.doc("organizations/o1/companies/c1/delegates/pending1").set(delegateDoc({
        uid: "pending1", status: "pending", nationalId: "28801010101011", nationalityID: "28801010101011",
      }));
      await db.doc("organizations/o1/companies/c1/photo_permissions/p1").set({
        companyUID: "c1", organizationUID: "o1", status: "pending",
      });
      await db.doc("organizations/o2/companies/c1/photo_permissions/p2").set({
        companyUID: "c1", organizationUID: "o2", status: "pending",
      });
    });
  });

  test("supervisor can read own-chain nested delegate", () =>
    assertSucceeds(getDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"))));

  test("supervisor can list own-chain delegates", () =>
    assertSucceeds(getDocs(collection(as("sup"), "organizations/o1/companies/c1/delegates"))));

  test("supervisor can read the same company on another chain", () =>
    assertSucceeds(getDoc(doc(as("sup"), "organizations/o2/companies/c1/delegates/d1"))));

  test("supervisor cannot read another company", () =>
    assertFails(getDoc(doc(as("sup"), "organizations/o3/companies/c2/delegates/dx"))));

  test("company admin can list the same company on another chain", () =>
    assertSucceeds(getDocs(collection(as("adm"), "organizations/o2/companies/c1/delegates"))));

  test("supervisor and admin cannot edit name and phone directly (M-1)", async () => {
    await assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      fullName: "اسم جديد", phoneNumber: "01000000099", updatedAt: "t",
    }));
    await assertFails(updateDoc(doc(as("adm"), "organizations/o2/companies/c1/delegates/d1"), {
      fullName: "اسم آخر", updatedAt: "t",
    }));
  });

  test("hr, accountant, marketing, and org-admin cannot edit name or phone", async () => {
    const patch = {fullName: "ممنوع", phoneNumber: "01000000999", updatedAt: "t"};
    await assertFails(updateDoc(doc(as("hr"), "organizations/o1/companies/c1/delegates/d1"), patch));
    await assertFails(updateDoc(doc(as("acc"), "organizations/o1/companies/c1/delegates/d1"), patch));
    await assertFails(updateDoc(doc(as("mkt"), "organizations/o1/companies/c1/delegates/d1"), patch));
    await assertFails(updateDoc(doc(as("org"), "organizations/o1/companies/c1/delegates/d1"), patch));
  });

  test("no company or org staff can change nationalId on an active delegate", async () => {
    const patch = {nationalId: "28801010101000", nationalityID: "28801010101000", updatedAt: "t"};
    await assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), patch));
    await assertFails(updateDoc(doc(as("adm"), "organizations/o1/companies/c1/delegates/d1"), patch));
    await assertFails(updateDoc(doc(as("org"), "organizations/o1/companies/c1/delegates/d1"), patch));
    await assertFails(updateDoc(doc(as("hr"), "organizations/o1/companies/c1/delegates/d1"), patch));
  });

  test("no company or org staff can change nationalId even on a pending signup record", async () => {
    const patch = {nationalId: "27701010101011", nationalityID: "27701010101011", updatedAt: "t"};
    await assertFails(updateDoc(doc(as("adm"), "organizations/o1/companies/c1/delegates/pending1"), patch));
    await assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/pending1"), patch));
    await assertFails(updateDoc(doc(as("org"), "organizations/o1/companies/c1/delegates/pending1"), patch));
  });

  test("super-admin and tech cannot client-write nationalId (TA-32)", async () => {
    const patch = {nationalId: "27701010101011", nationalityID: "27701010101011", updatedAt: "t"};
    await assertFails(updateDoc(doc(as("sa"), "organizations/o1/companies/c1/delegates/pending1"), patch));
    await assertFails(updateDoc(doc(as("ts"), "organizations/o1/companies/c1/delegates/pending1"), patch));
    await assertFails(updateDoc(doc(as("sa"), "organizations/o1/companies/c1/delegates/d1"), patch));
  });

  test("only super-admin and tech may activate or suspend a delegate", async () => {
    await assertFails(updateDoc(doc(as("org"), "organizations/o1/companies/c1/delegates/pending1"), {status: "active", updatedAt: "t"}));
    await assertFails(updateDoc(doc(as("adm"), "organizations/o1/companies/c1/delegates/pending1"), {status: "active", updatedAt: "t"}));
    await assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {status: "suspended", updatedAt: "t"}));
    await assertFails(updateDoc(doc(as("hr"), "organizations/o1/companies/c1/delegates/d1"), {status: "suspended", updatedAt: "t"}));
    await assertSucceeds(updateDoc(doc(as("sa"), "organizations/o1/companies/c1/delegates/d1"), {status: "suspended", updatedAt: "t"}));
    await assertSucceeds(updateDoc(doc(as("ts"), "organizations/o1/companies/c1/delegates/d1"), {status: "active", updatedAt: "t"}));
  });

  test("only super-admin and tech may approve or reject a photo permission", async () => {
    const path = "organizations/o1/companies/c1/photo_permissions/p1";
    await assertFails(updateDoc(doc(as("sup"), path), {status: "approved", updatedAt: "t"}));
    await assertFails(updateDoc(doc(as("adm"), path), {status: "rejected", updatedAt: "t"}));
    await assertFails(updateDoc(doc(as("org"), path), {status: "approved", updatedAt: "t"}));
    await assertFails(updateDoc(doc(as("mkt"), path), {status: "approved", updatedAt: "t"}));
    await assertSucceeds(updateDoc(doc(as("sa"), path), {status: "approved", updatedAt: "t"}));
    await assertSucceeds(updateDoc(doc(as("ts"), "organizations/o2/companies/c1/photo_permissions/p2"), {status: "rejected", updatedAt: "t"}));
  });

  test("supervisor can collection-group list photo_permissions by companyUID", async () => {
    const snap = await assertSucceeds(getDocs(query(
      collectionGroup(as("sup"), "photo_permissions"),
      where("companyUID", "==", "c1"),
    )));
    assert.equal(snap.size, 2);
  });

  test("company admin can collection-group list photo_permissions by companyUID", async () => {
    const snap = await assertSucceeds(getDocs(query(
      collectionGroup(as("adm"), "photo_permissions"),
      where("companyUID", "==", "c1"),
    )));
    assert.equal(snap.size, 2);
  });

  test("supervisor cannot collection-group list another company's photo_permissions", () =>
    assertFails(getDocs(query(
      collectionGroup(as("sup"), "photo_permissions"),
      where("companyUID", "==", "c2"),
    ))));

  test("supervisor can list photo_permissions on the nested own-chain path", () =>
    assertSucceeds(getDocs(collection(as("sup"), "organizations/o1/companies/c1/photo_permissions"))));

  test("company admin can list photo_permissions on another chain of the same company", () =>
    assertSucceeds(getDocs(collection(as("adm"), "organizations/o2/companies/c1/photo_permissions"))));
});
