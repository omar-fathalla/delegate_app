/**
 * Supervisor profile-edit rules: allowed fields, blocked keys, audit immutability.
 */
const assert = require("node:assert");
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc, updateDoc, getDoc, deleteDoc} = require("firebase/firestore");

const PROJECT_ID = "demo-profile-edit";
const USERS = {
  sa: {role: "super-admin", organizationUID: "o1"},
  ts: {role: "technical_support", organizationUID: "o1"},
  sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
  sup2: {role: "supervisor", organizationUID: "o1", companyUID: "c2"},
  adm: {role: "admin", organizationUID: "o1", companyUID: "c1"},
  d1: {role: "delegate", organizationUID: "o1", companyUID: "c1"},
};
const NESTED = "organizations/o1/companies/c1/delegates/d1";
const REQ = "delegate_requests/r1";
const BASE = {
  uid: "d1", organizationUID: "o1", companyUID: "c1", status: "active",
  fullName: "مندوب تجريبي", phoneNumber: "01999001001",
  nationalId: "29901010101011", nationalityID: "29901010101011",
  profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
  documents: [{documentKey: "personalPhoto", documentStatus: "approved", documentURL: "p0"}],
};
const REQDOC = {
  requestType: "new_delegate", status: "pending", organizationUID: "o1", companyUID: "c1",
  supervisorUid: "sup", fullName: "مندوب تجريبي", phoneNumber: "01999001001",
  nationalId: "29901010101011", profileImageUrl: "p0",
};

describe("supervisor delegate profile edit rules", () => {
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
      await db.doc(NESTED).set(BASE);
      await db.doc(REQ).set(REQDOC);
    });
  });

  test("supervisor can read own-company nested delegate", () =>
    assertSucceeds(getDoc(doc(as("sup"), NESTED))));

  test("other-company supervisor cannot read the delegate", () =>
    assertFails(getDoc(doc(as("sup2"), NESTED))));

  test("supervisor may update name, phone, and ID images on own-company delegate", () =>
    assertSucceeds(updateDoc(doc(as("sup"), NESTED), {
      fullName: "اسم جديد",
      firstName: "اسم",
      lastName: "جديد",
      phoneNumber: "01999001002",
      nationalIdFrontUrl: "f1",
      nationalIdBackUrl: "b1",
      profileImageUrl: "p1",
      personalPhotoURL: "p1",
      updatedAt: "t",
    })));

  test("supervisor cannot change nationalId", () =>
    assertFails(updateDoc(doc(as("sup"), NESTED), {nationalId: "28801010101011", updatedAt: "t"})));

  test("supervisor cannot change nationalityID", () =>
    assertFails(updateDoc(doc(as("sup"), NESTED), {nationalityID: "28801010101011", updatedAt: "t"})));

  test("supervisor cannot change status to approved", () =>
    assertFails(updateDoc(doc(as("sup"), NESTED), {status: "approved", updatedAt: "t"})));

  test("supervisor cannot change companyUID or organizationUID", () =>
    assertFails(updateDoc(doc(as("sup"), NESTED), {companyUID: "c2", updatedAt: "t"})));

  test("supervisor may update profile fields on a pending request", () =>
    assertSucceeds(updateDoc(doc(as("sup"), REQ), {fullName: "اسم جديد", phoneNumber: "01999001003"})));

  test("supervisor cannot change nationalId on a pending request", () =>
    assertFails(updateDoc(doc(as("sup"), REQ), {nationalId: "28801010101011"})));

  test("other-company supervisor cannot update the request", () =>
    assertFails(updateDoc(doc(as("sup2"), REQ), {fullName: "اسم"})));

  const audit = {
    actorUid: "sup",
    actorName: "مشرف",
    actorRole: "supervisor",
    field: "fullName",
    oldValue: "قديم",
    newValue: "جديد",
    delegateUid: "d1",
    delegateName: "مندوب",
    companyUID: "c1",
    companyName: "شركة",
    organizationUID: "o1",
    source: "direct_edit",
  };

  test("supervisor can create an audit record for their company", () =>
    assertSucceeds(setDoc(doc(as("sup"), "delegate_profile_audit_logs/a1"), audit)));

  test("supervisor cannot create an audit record for another company", () =>
    assertFails(setDoc(doc(as("sup"), "delegate_profile_audit_logs/a2"), {...audit, companyUID: "c2"})));

  test("audit records are immutable: supervisor cannot update or delete", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("delegate_profile_audit_logs/a3").set(audit);
    });
    await assertFails(updateDoc(doc(as("sup"), "delegate_profile_audit_logs/a3"), {newValue: "hack"}));
    await assertFails(deleteDoc(doc(as("sup"), "delegate_profile_audit_logs/a3")));
    await assertFails(updateDoc(doc(as("sa"), "delegate_profile_audit_logs/a3"), {newValue: "hack"}));
    await assertFails(deleteDoc(doc(as("sa"), "delegate_profile_audit_logs/a3")));
  });

  test("supervisor can read own-company audit records", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("delegate_profile_audit_logs/a4").set(audit);
    });
    await assertSucceeds(getDoc(doc(as("sup"), "delegate_profile_audit_logs/a4")));
    await assertFails(getDoc(doc(as("sup2"), "delegate_profile_audit_logs/a4")));
  });
});
