/**
 * TA-8 rules gaps (Mohamed 14 Nov): emulator-only probes.
 * npm: npx firebase-tools emulators:exec --only firestore --project demo-ta8-gaps "node --test test/rules/company-scoping-gaps.test.js"
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, updateDoc, setDoc} = require("firebase/firestore");

describe("TA-8 security rules gaps", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-ta8-gaps",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sup").set({
        role: "supervisor", organizationUID: "o1", companyUID: "c1", isActive: false,
      });
      await db.doc("users/hr").set({role: "hr", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/oa").set({
        role: "organization-admin", organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("users/mk").set({role: "marketing", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/d1").set({
        role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d1", status: "active",
      });
      await db.doc("organizations/o1/companies/c1/delegates/d1").set({
        organizationUID: "o1", companyUID: "c1", status: "active", phoneNumber: "01011111111",
      });
      await db.doc("delegate_requests/r1").set({
        requestType: "renewal", status: "pending", organizationUID: "o1", companyUID: "c1",
        supervisorUid: "sup",
      });
    });
  });

  test("DENY company staff reassigns supervisorUid on a delegate_request (gap a)", () =>
    assertFails(updateDoc(doc(as("sup"), "delegate_requests/r1"), {
      supervisorUid: "hr", updatedAt: "t",
    })));

  test("DENY company staff mutates requestType on a delegate_request (gap a)", () =>
    assertFails(updateDoc(doc(as("hr"), "delegate_requests/r1"), {
      requestType: "new_delegate", updatedAt: "t",
    })));

  test("ALLOW company staff may still touch updatedAt only", () =>
    assertSucceeds(updateDoc(doc(as("sup"), "delegate_requests/r1"), {updatedAt: "t"})));

  test("ALLOW company staff may cancel unpaid renewal", () =>
    assertSucceeds(updateDoc(doc(as("sup"), "delegate_requests/r1"), {status: "cancelled"})));

  test("DENY marketing cannot update delegate_requests (gap a)", () =>
    assertFails(updateDoc(doc(as("mk"), "delegate_requests/r1"), {updatedAt: "t"})));

  test("DENY supervisor self-activates isActive on own users doc (gap b)", () =>
    assertFails(updateDoc(doc(as("sup"), "users/sup"), {isActive: true})));

  test("DENY supervisor self-activates via isActive on own users doc as company staff", () =>
    assertFails(updateDoc(doc(as("sup"), "users/sup"), {displayName: "S", isActive: true})));

  test("DENY company staff may not set isActive true on another staff user", () =>
    assertFails(updateDoc(doc(as("oa"), "users/sup"), {isActive: true})));

  test("ALLOW org-admin may still deactivate staff", () =>
    assertSucceeds(updateDoc(doc(as("oa"), "users/sup"), {isActive: false})));

  test("DENY H-1: supervisor cannot suspend delegate via status spelling bypass", () =>
    assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "SUSPENDED", updatedAt: "t",
    })));

  test("DENY H-1: HR cannot deactivate delegate via isActive on nested delegate", () =>
    assertFails(updateDoc(doc(as("hr"), "organizations/o1/companies/c1/delegates/d1"), {
      isActive: false, updatedAt: "t",
    })));

  for (const st of ["disabled", "blocked", "rejected", "active ", " ACTIVE"]) {
    test(`DENY H-1: supervisor status variant '${st}' on delegate`, () =>
      assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
        status: st, updatedAt: "t",
      })));
  }

  test("ALLOW H-1: supervisor may still set delegate status pending (re-upload)", () =>
    assertSucceeds(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "pending", updatedAt: "t",
    })));
});