/**
 * Mohamed 2026-11-15: three delegate-status rules (emulator only).
 * npm run test:rules:status-guards
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, updateDoc, setDoc} = require("firebase/firestore");

const PATH = "organizations/o1/companies/c1/delegates/d1";
const PHOTO_APPROVED = {
  documentKey: "personalPhoto",
  documentStatus: "approved",
  documentURL: "https://cdn.example/p0.jpg",
  uploadedAt: "2026-01-01",
};
const ACTIVE = {
  organizationUID: "o1",
  companyUID: "c1",
  status: "active",
  phoneNumber: "01011111111",
  profileImageUrl: "https://cdn.example/p0.jpg",
  personalPhotoURL: "https://cdn.example/p0.jpg",
  photoURL: "https://cdn.example/p0.jpg",
  documents: [PHOTO_APPROVED],
};

function reuploadPending(extra = {}) {
  return {
    status: "pending",
    updatedAt: "t",
    profileImageUrl: "https://cdn.example/p1.jpg",
    personalPhotoURL: "https://cdn.example/p1.jpg",
    photoURL: "https://cdn.example/p1.jpg",
    documents: [{
      documentKey: "personalPhoto",
      documentStatus: "pending",
      documentURL: "https://cdn.example/p1.jpg",
      uploadedAt: "2026-11-15",
    }],
    ...extra,
  };
}

describe("delegate status guards (Mohamed 2026-11-15)", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-status-guards",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const staff = {
        sa: {role: "super-admin"},
        ts: {role: "technical_support", organizationUID: "o1"},
        sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
        csup: {role: "company_supervisor", organizationUID: "o1", companyUID: "c1"},
        ca: {role: "company-admin", organizationUID: "o1", companyUID: "c1"},
        hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
        acc: {role: "accountant", organizationUID: "o1", companyUID: "c1"},
        mk: {role: "marketing", organizationUID: "o1", companyUID: "c1"},
        admin1: {role: "admin", organizationUID: "o1", companyUID: "c1"},
      };
      for (const [id, data] of Object.entries(staff)) {
        await db.doc(`users/${id}`).set(data);
      }
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc(PATH).set(ACTIVE);
      await db.doc("organizations/o1/companies/c1/delegates/susp").set({
        ...ACTIVE,
        status: "suspended",
      });
      await db.doc("delegate_requests/new1").set({
        requestType: "new_delegate",
        status: "pending",
        paymentStatus: "pending",
        organizationUID: "o1",
        companyUID: "c1",
        supervisorUid: "sup",
        createdBy: "admin1",
        orgCompanyCheck: "ok",
      });
      await db.doc("delegate_requests/ren1").set({
        requestType: "renewal",
        status: "pending",
        paymentStatus: "pending",
        organizationUID: "o1",
        companyUID: "c1",
        supervisorUid: "sup",
      });
    });
  });

  describe("rule 1: active→pending only supervisor doc re-upload", () => {
    const denyBare = ["sup", "csup", "ca", "admin1", "hr"];
    for (const uid of denyBare) {
      test(`DENY ${uid} status-only active→pending`, () =>
        assertFails(updateDoc(doc(as(uid), PATH), {status: "pending", updatedAt: "t"})));
    }
    test("ALLOW super-admin may set active delegate pending (status-only)", () =>
      assertSucceeds(updateDoc(doc(as("sa"), PATH), {status: "pending", updatedAt: "t"})));
    test("ALLOW supervisor re-upload shape active→pending", () =>
      assertSucceeds(updateDoc(doc(as("sup"), PATH), {
        status: "pending",
        updatedAt: "t",
        documents: [{
          documentKey: "personalPhoto",
          documentStatus: "pending",
          documentURL: "https://cdn.example/p1.jpg",
          uploadedAt: "2026-11-15",
        }],
      })));
    test("ALLOW supervisor photo re-upload with all photo URL fields", () =>
      assertSucceeds(updateDoc(doc(as("sup"), PATH), reuploadPending())));
    test("ALLOW supervisor nationalityId re-upload with ID URL fields", () =>
      assertSucceeds(updateDoc(doc(as("sup"), PATH), {
        status: "pending",
        updatedAt: "t",
        nationalIdFrontUrl: "https://cdn.example/id-front.jpg",
        nationalIdBackUrl: "https://cdn.example/id-back.jpg",
        documents: [{
          documentKey: "nationalityId",
          documentStatus: "pending",
          documentURL: "https://cdn.example/id-front.jpg",
          secondaryURL: "https://cdn.example/id-back.jpg",
          uploadedAt: "2026-11-15",
        }],
      })));
    test("DENY company_admin re-upload shape active→pending", () =>
      assertFails(updateDoc(doc(as("ca"), PATH), reuploadPending())));
  });

  describe("rule 2: suspension lift global staff only", () => {
    const suspPath = "organizations/o1/companies/c1/delegates/susp";
    for (const uid of ["sup", "csup", "ca", "hr", "acc"]) {
      test(`DENY ${uid} suspended→active`, () =>
        assertFails(updateDoc(doc(as(uid), suspPath), {status: "active", updatedAt: "t"})));
      test(`DENY ${uid} suspended→pending`, () =>
        assertFails(updateDoc(doc(as(uid), suspPath), {status: "pending", updatedAt: "t"})));
    }
    test("ALLOW technical_support suspended→active", () =>
      assertSucceeds(updateDoc(doc(as("ts"), suspPath), {status: "active", updatedAt: "t"})));
    test("ALLOW super-admin suspended→pending", () =>
      assertSucceeds(updateDoc(doc(as("sa"), suspPath), {status: "pending", updatedAt: "t"})));
  });

  describe("rule 3: unpaid new_delegate cancel", () => {
    test("ALLOW supervisor cancel", () =>
      assertSucceeds(updateDoc(doc(as("sup"), "delegate_requests/new1"), {status: "cancelled"})));
    test("ALLOW createdBy cancel", () =>
      assertSucceeds(updateDoc(doc(as("admin1"), "delegate_requests/new1"), {status: "cancelled"})));
    for (const uid of ["hr", "acc", "mk", "ca"]) {
      test(`DENY ${uid} cancel unpaid new_delegate`, () =>
        assertFails(updateDoc(doc(as(uid), "delegate_requests/new1"), {status: "cancelled"})));
    }
    test("ALLOW supervisor cancel unpaid renewal (unchanged)", () =>
      assertSucceeds(updateDoc(doc(as("sup"), "delegate_requests/ren1"), {status: "cancelled"})));
    test("ALLOW HR cancel unpaid renewal (unchanged)", () =>
      assertSucceeds(updateDoc(doc(as("hr"), "delegate_requests/ren1"), {status: "cancelled"})));
    test("DENY cancel new_delegate when paymentStatus is PAID (case)", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(ctx.firestore().doc("delegate_requests/paid-case"), {
          requestType: "new_delegate",
          status: "approved",
          paymentStatus: "PAID",
          organizationUID: "o1",
          companyUID: "c1",
          supervisorUid: "sup",
          createdBy: "admin1",
        });
      });
      await assertFails(updateDoc(doc(as("sup"), "delegate_requests/paid-case"), {status: "cancelled"}));
    });
  });
});