/**
 * Docs-pending (FIX_PLAN_DOCS_PENDING, Mohamed 2026-11-04).
 * A delegate re-upload must be 'pending'; only super-admin (any company) or
 * company admin / supervisor of the SAME company can approve. Matching is by
 * documentKey. Emulator only (project demo-docs-pending).
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc, updateDoc} = require("firebase/firestore");

const PROJECT_ID = "demo-docs-pending";
const USERS = {
  sa: {role: "super-admin", organizationUID: "o1"},
  ca: {role: "company-admin", organizationUID: "o1", companyUID: "c1"},
  adm: {role: "admin", organizationUID: "o1", companyUID: "c1"},
  sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
  sup2: {role: "supervisor", organizationUID: "o1", companyUID: "c2"},
  hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
  acc: {role: "accountant", organizationUID: "o1", companyUID: "c1"},
  bmm: {role: "branches_marketing_manager", organizationUID: "o1", companyUID: "c1"},
  mk: {role: "marketing", organizationUID: "o1"},
  oa: {role: "organization-admin", organizationUID: "o1"},
  ts: {role: "technical_support", organizationUID: "o1"},
  d1: {role: "delegate", organizationUID: "o1", companyUID: "c1"},
};
const PHOTO = {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "p0", uploadedAt: "2026-01-01"};
const NID = {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f0", secondaryURL: "b0", uploadedAt: "2026-01-01"};
const RCPT = {documentKey: "paymentReceipt", documentStatus: "approved", documentURL: "r0", receiptCode: "RC1"};
const BASE = {
  uid: "d1", organizationUID: "o1", companyUID: "c1", status: "active", fullName: "Fake",
  profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
  documents: [PHOTO, NID, RCPT],
};
const PATHS = {
  nested: "organizations/o1/companies/c1/delegates/d1",
  group: "branches/x1/delegates/d1",
};

describe("docs-pending rules", () => {
  let env;
  const as = (uid, c = {}) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}, ...c}).firestore();
  const del = () => as("d1", {role: "delegate"});

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
      await db.doc("organizations/o1").set({name: "O1"});
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc("organizations/o1/companies/c2").set({name: "C2"});
      for (const p of Object.values(PATHS)) await db.doc(p).set(BASE);
      await db.doc("organizations/o1/companies/c1/delegates/pend").set({
        ...BASE, uid: "pend", status: "pending",
        documents: [{...PHOTO, documentStatus: "pending"}, {...NID, documentStatus: "pending"}]});
      await db.doc("delegate_requests/d1").set({
        status: "pending", organizationUID: "o1", companyUID: "c1", profileImageUrl: "p0",
        documents: [{...PHOTO, documentStatus: "pending"}]});
    });
  });

  const withDocs = (docs, extra = {}) => ({documents: docs, updatedAt: "t", ...extra});

  for (const [label, path] of Object.entries(PATHS)) {
    describe(`delegate self-update (${label})`, () => {
      const deny = (name, data) => test(`DENY ${name}`, () => assertFails(updateDoc(doc(del(), path), data)));
      const allow = (name, data) => test(`ALLOW ${name}`, () => assertSucceeds(updateDoc(doc(del(), path), data)));

      deny("re-upload photo with new URL as approved",
        withDocs([{...PHOTO, documentURL: "p1"}, NID, RCPT], {profileImageUrl: "p1"}));
      deny("re-upload as 'Approved' (capital)",
        withDocs([{...PHOTO, documentURL: "p1", documentStatus: "Approved"}, NID, RCPT], {profileImageUrl: "p1"}));
      test("DENY flip pending -> approved, same URL", async () => {
        await env.withSecurityRulesDisabled((c) => c.firestore().doc(path).update({documents: [{...PHOTO, documentStatus: "pending"}, NID, RCPT]}));
        await assertFails(updateDoc(doc(del(), path), withDocs([PHOTO, NID, RCPT])));
      });
      deny("append a new approved entry",
        withDocs([PHOTO, NID, RCPT, {documentKey: "healthCertificate", documentStatus: "approved", documentURL: "h1"}]));
      deny("keep approved entry but swap its documentURL", withDocs([PHOTO, {...NID, documentURL: "fX"}, RCPT]));
      deny("keep approved entry but swap its secondaryURL", withDocs([PHOTO, {...NID, secondaryURL: "bX"}, RCPT]));
      deny("approved entry with unknown documentKey", withDocs([PHOTO, NID, RCPT, {documentKey: "bogus", documentStatus: "approved", documentURL: "p0"}]));
      deny("move approved status onto another key with same URL",
        withDocs([PHOTO, NID, {...RCPT, documentKey: "electronicPaymentReceipt"}]));
      deny("change profileImageUrl without touching documents", {profileImageUrl: "p1", updatedAt: "t"});
      test("DENY full replace that drops documents and sets a new photo URL", () => {
          const {documents: _drop, ...rest} = BASE;
          return assertFails(setDoc(doc(del(), path), {...rest, profileImageUrl: "p9"}));
        });
      test("ALLOW full replace without documents when no URL changes (legacy full-map save)", () => {
        const {documents: _drop, ...rest} = BASE;
        return assertSucceeds(setDoc(doc(del(), path), rest));
      });
      deny("documents list longer than 8", withDocs(Array.from({length: 9}, (_, i) => ({documentKey: "x" + i, documentStatus: "pending"}))));
      deny("self-edit fullName (still blocked)", {fullName: "Other"});

      allow("re-upload photo as pending, others unchanged",
        withDocs([{...PHOTO, documentURL: "p1", documentStatus: "pending"}, NID, RCPT], {profileImageUrl: "p1", personalPhotoURL: "p1", photoURL: "p1"}));
      allow("remove earlier entry (photo @0); later approved entries shift index",
        withDocs([NID, RCPT], {profileImageUrl: null}));
      allow("reorder approved entries without change", withDocs([RCPT, PHOTO, NID]));
      allow("full-map save with documents unchanged", {...BASE, updatedAt: "t"});
      allow("national ID back re-upload as pending",
        withDocs([PHOTO, {...NID, secondaryURL: "b1", documentStatus: "pending"}, RCPT], {nationalIdBackUrl: "b1"}));
    });
  }

  describe("expression budget (worst case)", () => {
    const keys = ["personalPhoto", "nationalityId", "authorizationLetter", "insuranceLetter",
      "healthCertificate", "paymentReceipt", "electronicPaymentReceipt"];
    const seven = keys.map((k) => ({documentKey: k, documentStatus: "approved", documentURL: k + "0"}));
    for (const [label, path] of Object.entries(PATHS)) {
      test(`ALLOW 7 approved, reversed order, + 1 pending re-upload (${label})`, async () => {
        await env.withSecurityRulesDisabled((c) => c.firestore().doc(path).update({documents: seven}));
        const next = [...seven].reverse();
        next[0] = {...next[0], documentURL: "new", documentStatus: "pending"};
        await assertSucceeds(updateDoc(doc(del(), path), {documents: next, updatedAt: "t"}));
      });
    }
    test("ALLOW hr non-approval write on nested delegate with 7 approved entries", async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(PATHS.nested).update({documents: seven}));
      await assertSucceeds(updateDoc(doc(as("hr"), PATHS.nested), {documents: [...seven].reverse(), notes: "x"}));
    });
  });

  describe("staff approval (S1)", () => {
    const pendPath = "organizations/o1/companies/c1/delegates/pend";
    const approveData = {documents: [{...PHOTO, documentStatus: "approved", reviewedBy: "x"}, {...NID, documentStatus: "pending"}]};
    for (const who of ["sa", "ca", "adm", "sup"]) {
      test(`ALLOW ${who} approves`, () => assertSucceeds(updateDoc(doc(as(who), pendPath), approveData)));
    }
    for (const who of ["hr", "acc", "bmm", "mk", "oa", "ts", "sup2"]) {
      test(`DENY ${who} approves`, () => assertFails(updateDoc(doc(as(who), pendPath), approveData)));
    }
    test("ALLOW hr rejects (no approved introduced)", () => assertSucceeds(updateDoc(doc(as("hr"), pendPath),
      {documents: [{...PHOTO, documentStatus: "rejected", rejectionReason: "x"}, {...NID, documentStatus: "pending"}]})));
    test("ALLOW tech support signup approval (pending -> active with approved docs)", () =>
      assertSucceeds(updateDoc(doc(as("ts"), pendPath), {...approveData, status: "active"})));
    test("ALLOW super-admin approves in another company", async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc("organizations/o1/companies/c2/delegates/z").set({
        ...BASE, uid: "z", companyUID: "c2", documents: [{...PHOTO, documentStatus: "pending"}]}));
      await assertSucceeds(updateDoc(doc(as("sa"), "organizations/o1/companies/c2/delegates/z"), {documents: [PHOTO]}));
    });
  });

  describe("delegate_requests self lock", () => {
    const p = "delegate_requests/d1";
    test("DENY delegate sets status approved", () => assertFails(updateDoc(doc(del(), p), {status: "approved"})));
    test("DENY delegate approves its documents", () => assertFails(updateDoc(doc(del(), p), {documents: [PHOTO]})));
    test("DENY delegate writes other fields", () => assertFails(updateDoc(doc(del(), p), {fee: 0})));
    test("DENY delegate creates its own request", () => assertFails(setDoc(doc(del(), "delegate_requests/new1"), {status: "pending"})));
    test("ALLOW delegate updates profileImageUrl", () => assertSucceeds(updateDoc(doc(del(), p), {profileImageUrl: "p1", updatedAt: "t"})));
    test("ALLOW delegate re-upload as pending", () => assertSucceeds(updateDoc(doc(del(), p),
      {documents: [{...PHOTO, documentURL: "p1", documentStatus: "pending"}], profileImageUrl: "p1", updatedAt: "t"})));
    test("ALLOW company staff review update", () => assertSucceeds(updateDoc(doc(as("sup"), p), {status: "approved", reviewedBy: "s"})));
  });
});
