/**
 * TAS-331: delegate documents store a Storage object path next to the
 * legacy download URL (<field>Path on the doc, documentPath / secondaryPath
 * per documents[] entry). Emulator only (project demo-tas331).
 *
 * - A delegate's own write may set a path only inside its own folders, and
 *   a changed top-level path must be backed by a pending entry, like the URL.
 * - While the URL is still written next to the path, the URL must be the
 *   download URL of that same object.
 * - Tech-support activation binds each approved entry's path to the
 *   request's path, like the URL.
 * - Company / org staff still cannot write the image fields directly.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("./_rules_testing");
const {doc, updateDoc, writeBatch} = require("firebase/firestore");

const PROJECT_ID = "demo-tas331";
const BUCKET = "tashil-dev.firebasestorage.app";
const url = (p) => `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(p)}?alt=media&token=t`;

const USERS = {
  sa: {role: "super-admin", organizationUID: "o1"},
  hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
  sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
  ts: {role: "technical_support", organizationUID: "o1"},
  d1: {role: "delegate", organizationUID: "o1", companyUID: "c1"},
};
const PHOTO = {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "p0", uploadedAt: "2026-01-01"};
const NID = {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f0", secondaryURL: "b0", uploadedAt: "2026-01-01"};
const RCPT = {documentKey: "paymentReceipt", documentStatus: "approved", documentURL: "r0", receiptCode: "RC1"};
const BASE = {
  uid: "d1", organizationUID: "o1", companyUID: "c1", status: "active", fullName: "Fake",
  profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", documents: [PHOTO, NID, RCPT],
};
const PATHS = {
  nested: "organizations/o1/companies/c1/delegates/d1",
  top: "delegates/d1",
  request: "delegate_requests/d1",
};
const P1 = "delegate_documents/d1/personalPhoto_1.jpg";
const F1 = "delegate_documents/d1/nationalIdFront_1.jpg";
const B1 = "delegate_documents/d1/nationalIdBack_1.jpg";
const R1 = "delegate_subscription_receipts/d1/receipt.jpg";

describe("TAS-331 delegate document paths", () => {
  let env;
  const as = (uid, c = {}) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}, ...c}).firestore();
  const del = () => as("d1", {role: "delegate"});
  const seed = (p, d) => env.withSecurityRulesDisabled((c) => c.firestore().doc(p).set(d));

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
      await db.doc(PATHS.nested).set(BASE);
      await db.doc(PATHS.top).set(BASE);
      await db.doc(PATHS.request).set({
        status: "pending", requestType: "new_delegate", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1", profileImageUrl: "p0",
        nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", receiptImageUrl: "r0",
        documents: [PHOTO, NID, RCPT]});
    });
  });

  const photoWrite = (u, p, entryExtra = {}) => ({
    documents: [{...PHOTO, documentStatus: "pending", documentURL: u, documentPath: p, ...entryExtra}, NID, RCPT],
    profileImageUrl: u, personalPhotoURL: u, profileImagePath: p, updatedAt: "t",
  });

  for (const [label, path] of Object.entries(PATHS)) {
    describe(`delegate self-write (${label})`, () => {
      const allow = (name, data) => test(`ALLOW ${name}`, () => assertSucceeds(updateDoc(doc(del(), path), data)));
      const deny = (name, data) => test(`DENY ${name}`, () => assertFails(updateDoc(doc(del(), path), data)));

      allow("photo path + its download URL (legacy URLs on)", photoWrite(url(P1), P1));
      allow("photo path only, URL '' (legacy URLs off)", photoWrite("", P1));
      deny("photo URL of another object than the path", photoWrite(url("delegate_documents/d1/other.jpg"), P1));
      allow("photo path backed through its URL (entry from an older writer has the URL only)", {
        ...photoWrite(url(P1), P1), documents: [{...PHOTO, documentStatus: "pending", documentURL: url(P1)}, NID, RCPT]});
      deny("photo path only, the pending entry holds another path", {
        ...photoWrite("", P1), documents: [{...PHOTO, documentStatus: "pending", documentURL: "",
          documentPath: "delegate_documents/d1/other.jpg"}, NID, RCPT]});
      deny("photo path backed only by an approved entry", {
        ...photoWrite("", P1), documents: [{...PHOTO, documentURL: "", documentPath: P1}, NID, RCPT]});
      deny("photo path in another delegate's folder",
        photoWrite(url("delegate_documents/d2/p.jpg"), "delegate_documents/d2/p.jpg"));
      deny("photo path climbing out of the folder (..)",
        photoWrite("", "delegate_documents/d1/../d2/p.jpg"));
      deny("photo path that is a URL", photoWrite("", url(P1)));
      deny("path only on the top level, no documents change", {profileImagePath: P1, updatedAt: "t"});
      deny("new pending entry with a foreign path (no top-level change)", {
        documents: [PHOTO, NID, RCPT, {documentKey: "healthCertificate", documentStatus: "pending",
          documentURL: "", documentPath: "delegate_documents/d2/h.jpg"}], updatedAt: "t"});
      allow("new pending entry with an own-folder path (no top-level change)", {
        documents: [PHOTO, NID, RCPT, {documentKey: "healthCertificate", documentStatus: "pending",
          documentURL: "", documentPath: "delegate_documents/d1/healthCertificate_1.jpg"}], updatedAt: "t"});
      allow("entry path in the HR web folder of the same delegate", {
        documents: [PHOTO, NID, RCPT, {documentKey: "healthCertificate", documentStatus: "pending",
          documentURL: "", documentPath: "organizations/o1/companies/c1/delegates/d1/h.jpg"}], updatedAt: "t"});
      deny("approved entry that gains a path", {
        documents: [{...PHOTO, documentPath: P1}, NID, RCPT], updatedAt: "t"});

      allow("ID front + back paths with their URLs", {
        documents: [PHOTO, {...NID, documentStatus: "pending", documentURL: url(F1), secondaryURL: url(B1),
          documentPath: F1, secondaryPath: B1}, RCPT],
        nationalIdFrontUrl: url(F1), nationalIdBackUrl: url(B1),
        nationalIdFrontPath: F1, nationalIdBackPath: B1, updatedAt: "t"});
      allow("ID back path only (URLs off)", {
        documents: [PHOTO, {...NID, documentStatus: "pending", secondaryURL: "", secondaryPath: B1}, RCPT],
        nationalIdBackUrl: "", nationalIdBackPath: B1, updatedAt: "t"});
      deny("ID back URL naming the front path", {
        documents: [PHOTO, {...NID, documentStatus: "pending", documentURL: url(F1), secondaryURL: url(F1),
          documentPath: F1, secondaryPath: B1}, RCPT],
        nationalIdFrontUrl: url(F1), nationalIdBackUrl: url(F1),
        nationalIdFrontPath: F1, nationalIdBackPath: B1, updatedAt: "t"});
      deny("ID front path backed by the back slot", {
        documents: [PHOTO, {...NID, documentStatus: "pending", secondaryURL: "", secondaryPath: F1}, RCPT],
        nationalIdFrontUrl: "", nationalIdFrontPath: F1, updatedAt: "t"});

      allow("receipt path with its URL", {
        documents: [PHOTO, NID, {...RCPT, documentStatus: "pending", documentURL: url(R1), documentPath: R1}],
        receiptImageUrl: url(R1), receiptImagePath: R1, updatedAt: "t"});
      deny("receipt path in another request's folder", {
        documents: [PHOTO, NID, {...RCPT, documentStatus: "pending", documentURL: "",
          documentPath: "delegate_subscription_receipts/d2/receipt.jpg"}],
        receiptImageUrl: "", receiptImagePath: "delegate_subscription_receipts/d2/receipt.jpg", updatedAt: "t"});
    });
  }

  test("ALLOW a multi-company delegate (delegateIds claim) writes a path in its sign-in folder", async () => {
    await seed("organizations/o1/companies/c1/delegates/d1b", {...BASE, uid: "d1b"});
    const p = "delegate_documents/d1/personalPhoto_2.jpg";
    await assertSucceeds(updateDoc(doc(as("d1", {role: "delegate", delegateIds: ["d1b"]}),
      "organizations/o1/companies/c1/delegates/d1b"), photoWrite(url(p), p)));
  });

  test("DENY company HR writes an image path directly (editDelegateProfile only)", () =>
    assertFails(updateDoc(doc(as("hr"), PATHS.nested), {profileImagePath: P1, updatedAt: "t"})));

  describe("tech-support client activation (old builds) still works with paths", () => {
    // Path binding for the activation lives in the approveDelegateDocuments
    // callable (functions/test/tas331_delegate_doc_paths.test.js); the
    // client batch keeps the URL binding only (budget).
    const NP = "organizations/o1/companies/c1/delegates/n1";
    const REQ = {status: "pending", requestType: "new_delegate", organizationUID: "o1", companyUID: "c1",
      supervisorUid: "sup", orgCompanyCheck: "ok", fullName: "Fake", nationalId: "",
      profileImageUrl: url(P1), profileImagePath: P1,
      nationalIdFrontUrl: url(F1), nationalIdFrontPath: F1, nationalIdBackUrl: url(B1), nationalIdBackPath: B1};
    const pPhoto = {...PHOTO, documentStatus: "pending", documentURL: url(P1), documentPath: P1};
    const pNid = {...NID, documentStatus: "pending", documentURL: url(F1), secondaryURL: url(B1),
      documentPath: F1, secondaryPath: B1};
    const batch = (db, data) => {
      const b = writeBatch(db);
      b.update(doc(db, "delegate_requests/n1"), {status: "approved", reviewedBy: "x", reviewedAt: "t"});
      b.update(doc(db, NP), data);
      return b.commit();
    };
    const approve = (docs) => docs.map((e) => ({...e, documentStatus: "approved", reviewedBy: "ts"}));

    test("ALLOW entries carrying the request's URLs and paths", async () => {
      await seed("delegate_requests/n1", REQ);
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: [pPhoto, pNid]});
      await assertSucceeds(batch(as("ts"), {status: "active", documents: approve([pPhoto, pNid]), updatedAt: "t"}));
    });
    test("DENY an entry URL that differs from the request", async () => {
      await seed("delegate_requests/n1", REQ);
      const bad = {...pPhoto, documentURL: url("delegate_documents/n1/other.jpg")};
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: [bad, pNid]});
      await assertFails(batch(as("ts"), {status: "active", documents: approve([bad, pNid]), updatedAt: "t"}));
    });
    test("DENY the activation changing an entry path", async () => {
      await seed("delegate_requests/n1", REQ);
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: [pPhoto, pNid]});
      const moved = approve([pPhoto, pNid]);
      moved[0].documentPath = "delegate_documents/n1/other.jpg";
      await assertFails(batch(as("ts"), {status: "active", documents: moved, updatedAt: "t"}));
    });
  });
});
