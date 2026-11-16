/**
 * Docs-pending (FIX_PLAN_DOCS_PENDING, Mohamed 2026-11-04).
 * A delegate re-upload must be 'pending'; only super-admin (any company) or
 * company admin / supervisor of the SAME company can approve. Matching is by
 * documentKey. Emulator only (project demo-docs-pending).
 */
const assert = require("node:assert");
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc, updateDoc, getDoc, deleteDoc, writeBatch} = require("firebase/firestore");

const PROJECT_ID = "demo-docs-pending";
// TA-60 integrator (PR #343): global-staff unbatched approve/provision (live prod / app cb3f4e2).
const TA60_UNBATCHED_STAFF_COMPAT = readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")
  .includes("globalStaffUnbatchedRequestApproveOk");
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
  oa: {role: "organization-admin", organizationUID: "o1", companyUID: "c1"},
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
        status: "pending", requestType: "new_delegate", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1", profileImageUrl: "p0",
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
    for (const who of ["ca", "adm", "sup"]) {
      test(`ALLOW ${who} approves`, () => assertSucceeds(updateDoc(doc(as(who), pendPath), approveData)));
    }
    for (const who of ["sa", "ts"]) {
      test(`DENY ${who} client approves (privileged callable)`, () =>
        assertFails(updateDoc(doc(as(who), pendPath), approveData)));
    }
    for (const who of ["hr", "acc", "bmm", "mk", "oa", "ts", "sup2"]) {
      test(`DENY ${who} approves`, () => assertFails(updateDoc(doc(as(who), pendPath), approveData)));
    }
    test("ALLOW hr rejects (no approved introduced)", () => assertSucceeds(updateDoc(doc(as("hr"), pendPath),
      {documents: [{...PHOTO, documentStatus: "rejected", rejectionReason: "x"}, {...NID, documentStatus: "pending"}]})));
    test("DENY tech support activation outside the request-approval batch [r4 F2]", () => {
      if (TA60_UNBATCHED_STAFF_COMPAT) {
        return assertSucceeds(updateDoc(doc(as("ts"), pendPath), {status: "active", updatedAt: "t"}));
      }
      return assertFails(updateDoc(doc(as("ts"), pendPath), {...approveData, status: "active"}));
    });
    test("ALLOW super-admin signup approval (pending -> active with approved docs)", () =>
      assertSucceeds(updateDoc(doc(as("sa"), pendPath), {...approveData, status: "active"})));
    test("DENY super-admin client approves in another company (privileged callable)", async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc("organizations/o1/companies/c2/delegates/z").set({
        ...BASE, uid: "z", companyUID: "c2", documents: [{...PHOTO, documentStatus: "pending"}]}));
      await assertFails(updateDoc(doc(as("sa"), "organizations/o1/companies/c2/delegates/z"), {documents: [PHOTO]}));
    });
    // Anti-fraud: company-level roles must not flip a delegate to active/approved.
    // The previous rule allowed a same-company supervisor/admin to set status
    // via the approver shortcut (staffDocsApproveOk).
    for (const who of ["ca", "adm", "sup", "hr"]) {
      test(`DENY ${who} sets pending delegate status to active`, () =>
        assertFails(updateDoc(doc(as(who), pendPath), {status: "active"})));
      test(`DENY ${who} sets pending delegate status to approved`, () =>
        assertFails(updateDoc(doc(as(who), pendPath), {status: "approved"})));
    }
    test("DENY company supervisor activates while also approving documents", () =>
      assertFails(updateDoc(doc(as("sup"), pendPath), {...approveData, status: "active"})));
    test("DENY org-admin sets status to active without changing documents", () =>
      assertFails(updateDoc(doc(as("oa"), pendPath), {status: "active"})));
  });

  describe("delegate_requests self lock", () => {
    const p = "delegate_requests/d1";
    test("DENY delegate sets status approved", () => assertFails(updateDoc(doc(del(), p), {status: "approved"})));
    test("DENY delegate approves its documents", () => assertFails(updateDoc(doc(del(), p), {documents: [PHOTO]})));
    test("DENY delegate writes other fields", () => assertFails(updateDoc(doc(del(), p), {fee: 0})));
    test("DENY delegate creates its own request", () => assertFails(setDoc(doc(del(), "delegate_requests/new1"), {status: "pending"})));
    test("DENY delegate updates profileImageUrl without a pending entry (L4)", () => assertFails(updateDoc(doc(del(), p), {profileImageUrl: "p1", updatedAt: "t"})));
    test("ALLOW delegate removes profileImageUrl", () => assertSucceeds(updateDoc(doc(del(), p), {profileImageUrl: "", updatedAt: "t"})));
    test("ALLOW delegate re-upload as pending", () => assertSucceeds(updateDoc(doc(del(), p),
      {documents: [{...PHOTO, documentURL: "p1", documentStatus: "pending"}], profileImageUrl: "p1", updatedAt: "t"})));
    test("DENY company staff approve or change request status", () => assertFails(updateDoc(doc(as("sup"), p), {status: "approved", reviewedBy: "s"})));
    test("DENY company staff profile-field request edit (M-1)", () => assertFails(updateDoc(doc(as("sup"), p), {firstName: "Edited", updatedAt: "t"})));
    test("ALLOW company staff non-sensitive request edit in their company", () => assertSucceeds(updateDoc(doc(as("sup"), p), {updatedAt: "t"})));
    test("DENY company staff change nationalId or companyUID", () => assertFails(updateDoc(doc(as("sup"), p), {nationalId: "x", companyUID: "c9"})));
    test("DENY company staff of another company edit the request", () => assertFails(updateDoc(doc(as("sup2"), p), {firstName: "x"})));
    test("ALLOW company staff cancel an unpaid/pending request", () => assertSucceeds(updateDoc(doc(as("sup"), p), {status: "cancelled"})));
  });
});

/**
 * PR #208 round 2 (FIX_PLAN_PR208_r2): B1 group-path staff, B2 URL side
 * door, M1 self-approve, L1 status type, L2 unchanged unknown keys.
 */
describe("docs-pending round 2", () => {
  let env;
  const as = (uid, c = {}) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}, ...c}).firestore();
  const del = () => as("d1", {role: "delegate"});
  // A rules evaluation error makes the emulator client retry forever; fail
  // fast instead of hanging (B1 regression).
  const T = (p) => Promise.race([p, new Promise((_, r) => setTimeout(() => r(new Error("TIMEOUT_EMULATOR_ERROR")), 5000))]);
  const ok = (p) => T(assertSucceeds(p));
  const no = (p) => T(assertFails(p));
  const compatNo = (p) => T(TA60_UNBATCHED_STAFF_COMPAT ? assertSucceeds(p) : assertFails(p));
  const ALL = {
    nested: "organizations/o1/companies/c1/delegates/d1",
    top: "delegates/d1",
    branch: "branches/x1/delegates/d1",
  };
  const KEYS = ["personalPhoto", "nationalityId", "authorizationLetter", "insuranceLetter",
    "healthCertificate", "paymentReceipt", "electronicPaymentReceipt", "electronic_payment_receipt"];
  const EIGHT = KEYS.map((k) => ({documentKey: k, documentStatus: "approved", documentURL: k + "0",
    secondaryURL: "s", uploadedAt: "2026-01-01", reviewedBy: "x"}));
  const PEND = {...BASE, documents: [{...PHOTO, documentStatus: "pending"}, NID, RCPT]};
  const APPROVE = {documents: [{...PHOTO, reviewedBy: "r"}, NID, RCPT]};
  const seed = (p, d) => env.withSecurityRulesDisabled((c) => c.firestore().doc(p).set(
    p.startsWith("delegate_requests/") && d && !Object.prototype.hasOwnProperty.call(d, "orgCompanyCheck")
      ? {...d, orgCompanyCheck: "ok"}
      : d));
  // r4: the app's approve batch: request pending -> approved + delegate write.
  const REQ = {status: "pending", requestType: "new_delegate", organizationUID: "o1", companyUID: "c1",
    supervisorUid: "sup", fullName: "Fake", nationalId: "", profileImageUrl: "p0",
    nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", receiptImageUrl: "r0"};
  const batchApprove = (db, rid, path, data, create = false, reqData = {}) => {
    const b = writeBatch(db);
    b.update(doc(db, `delegate_requests/${rid}`), {status: "approved", reviewedBy: "x", reviewedAt: "t", ...reqData});
    if (create) b.set(doc(db, path), data); else b.update(doc(db, path), data);
    return b.commit();
  };
  const readReq = async (rid) => {
    let st;
    await env.withSecurityRulesDisabled(async (c) => { st = (await c.firestore().doc(`delegate_requests/${rid}`).get()).data().status; });
    return st;
  };

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
      await db.doc("organizations/o2").set({name: "O2"});
      await db.doc("organizations/o2/companies/c1").set({name: "C1", organizationUID: "o2"});
      for (const p of Object.values(ALL)) await db.doc(p).set(BASE);
      await db.doc("delegate_requests/d1").set({
        status: "pending", requestType: "new_delegate", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1", profileImageUrl: "p0",
        nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", documents: BASE.documents});
    });
  });

  for (const [label, path] of Object.entries({top: ALL.top, branch: ALL.branch})) {
    describe(`B1 staff on group path (${label})`, () => {
      for (const w of ["sa", "ts"]) {
        test(`ALLOW ${w} plain edit (no emulator error)`, () => ok(updateDoc(doc(as(w), path), {fullName: "z"})));
      }
      for (const w of ["ca", "sup"]) {
        test(`DENY ${w} plain name edit (callable-only, M-1)`, () => no(updateDoc(doc(as(w), path), {fullName: "z"})));
      }
      // Mohamed 2026-11-10: only company admin/supervisor may edit name/phone/photo.
      test("DENY hr name edit (company editor policy)", () => no(updateDoc(doc(as("hr"), path), {fullName: "z"})));
      test("ALLOW hr plain non-profile edit (no emulator error)", () => ok(updateDoc(doc(as("hr"), path), {notes: "z"})));
      for (const w of ["ca", "adm", "sup"]) {
        test(`ALLOW ${w} approves pending entry`, async () => {
          await seed(path, PEND); await ok(updateDoc(doc(as(w), path), APPROVE));
        });
      }
      for (const w of ["sa", "ts", "sup2", "hr", "acc"]) {
        test(`DENY ${w} approves pending entry (privileged callable)`, async () => {
          await seed(path, PEND); await no(updateDoc(doc(as(w), path), APPROVE));
        });
      }
      for (const w of ["sup", "hr"]) {
        test(`ALLOW ${w} rejects pending entry`, async () => {
          await seed(path, PEND);
          await ok(updateDoc(doc(as(w), path), {documents: [{...PHOTO, documentStatus: "rejected", rejectionReason: "x"}, NID, RCPT]}));
        });
      }
      test("ALLOW hr budget write: 8 approved reversed + other field", async () => {
        await seed(path, {...BASE, documents: EIGHT});
        await ok(updateDoc(doc(as("hr"), path), {documents: [...EIGHT].reverse(), notes: "x"}));
      });
      test("ALLOW sup approves all 8 (worst-case staff budget)", async () => {
        await seed(path, {...BASE, documents: EIGHT.map((e) => ({...e, documentStatus: "pending"}))});
        await ok(updateDoc(doc(as("sup"), path), {documents: [...EIGHT].reverse()}));
      });
      test("DENY hr approves 1 of 8 (deny, not error)", async () => {
        await seed(path, {...BASE, documents: EIGHT.map((e) => ({...e, documentStatus: "pending"}))});
        await no(updateDoc(doc(as("hr"), path), {documents: [EIGHT[0], ...EIGHT.slice(1).map((e) => ({...e, documentStatus: "pending"}))]}));
      });
    });
  }

  for (const [label, path] of Object.entries({...ALL, request: "delegate_requests/d1"})) {
    describe(`B2 URL must be backed by a pending entry (${label})`, () => {
      const allow = (n, f) => test(`ALLOW ${n}`, async () => ok(updateDoc(doc(del(), path), await f())));
      const deny = (n, f) => test(`DENY ${n}`, async () => no(updateDoc(doc(del(), path), await f())));
      deny("photo fields set to two different URLs", () =>
        ({documents: [{...PHOTO, documentStatus: "pending", documentURL: "p1"}, NID, RCPT], profileImageUrl: "p1", personalPhotoURL: "pE"}));
      deny("drop photo entry + new profileImageUrl/photoURL", () => ({documents: [NID, RCPT], profileImageUrl: "pE", photoURL: "pE"}));
      deny("pending photo entry with empty URL + new profileImageUrl", () =>
        ({documents: [{documentKey: "personalPhoto", documentStatus: "pending", documentURL: ""}, NID, RCPT], profileImageUrl: "pE"}));
      deny("legacy (no photo entry), touch NID pending + new photoURL", async () => {
        await seed(path, {...BASE, documents: [NID]});
        return {documents: [{...NID, documentStatus: "pending"}], photoURL: "pE", profileImageUrl: "pE"};
      });
      deny("drop nationalityId entry + new nationalIdFrontUrl", () => ({documents: [PHOTO, RCPT], nationalIdFrontUrl: "fE"}));
      deny("pending photo entry with a different URL", () =>
        ({documents: [{...PHOTO, documentStatus: "pending", documentURL: "p1"}, NID, RCPT], profileImageUrl: "pE"}));
      deny("matching entry status 'Pending' (must be exactly 'pending')", () =>
        ({documents: [{...PHOTO, documentStatus: "Pending", documentURL: "p1"}, NID, RCPT], profileImageUrl: "p1"}));
      deny("matching URL but wrong key", () =>
        ({documents: [PHOTO, NID, RCPT, {documentKey: "healthCertificate", documentStatus: "pending", documentURL: "pE"}], profileImageUrl: "pE"}));
      deny("reorder (approved kept) + new profileImageUrl (L3)", () => ({documents: [NID, PHOTO, RCPT], profileImageUrl: "pE"}));
      deny("URL only, no documents (L4)", () => ({profileImageUrl: "pE", updatedAt: "t"}));
      deny("ID back URL backed only by documentURL (must be secondaryURL)", () =>
        ({documents: [PHOTO, {...NID, documentStatus: "pending", documentURL: "bE"}, RCPT], nationalIdBackUrl: "bE"}));
      allow("photo re-upload: pending entry with same URL in all photo fields", () => ({
        documents: [{...PHOTO, documentStatus: "pending", documentURL: "p1"}, NID, RCPT],
        profileImageUrl: "p1", personalPhotoURL: "p1", ...(label === "request" ? {} : {photoURL: "p1"}), updatedAt: "t"}));
      allow("ID front re-upload", () =>
        ({documents: [PHOTO, {...NID, documentStatus: "pending", documentURL: "f1"}, RCPT], nationalIdFrontUrl: "f1"}));
      allow("ID back re-upload", () =>
        ({documents: [PHOTO, {...NID, documentStatus: "pending", secondaryURL: "b1"}, RCPT], nationalIdBackUrl: "b1"}));
      allow("receipt re-upload", () =>
        ({documents: [PHOTO, NID, {...RCPT, documentStatus: "pending", documentURL: "r1"}], receiptImageUrl: "r1"}));
      allow("budget: 8 entries, photo re-upload backing entry in slot 7", async () => {
        await seed(path, {...BASE, documents: EIGHT});
        return {documents: [...EIGHT.slice(1).reverse(), {...EIGHT[0], documentStatus: "pending", documentURL: "p9"}],
          profileImageUrl: "p9", personalPhotoURL: "p9", updatedAt: "t"};
      });
      allow("budget: 8 entries, ID front+back re-upload backing entry in slot 7", async () => {
        await seed(path, {...BASE, documents: EIGHT});
        const rest = EIGHT.filter((e) => e.documentKey !== "nationalityId").reverse();
        return {documents: [...rest, {...EIGHT[1], documentStatus: "pending", documentURL: "f9", secondaryURL: "b9"}],
          nationalIdFrontUrl: "f9", nationalIdBackUrl: "b9", updatedAt: "t"};
      });
      allow("photo removal (empty URL)", () => ({profileImageUrl: "", personalPhotoURL: "", updatedAt: "t"}));
      allow("photo + ID front/back in one write (3 entries)", () => ({
        documents: [{...PHOTO, documentStatus: "pending", documentURL: "p9"}, RCPT,
          {...NID, documentStatus: "pending", documentURL: "f9", secondaryURL: "b9"}],
        profileImageUrl: "p9", personalPhotoURL: "p9", nationalIdFrontUrl: "f9", nationalIdBackUrl: "b9", updatedAt: "t"}));
      // Photo AND ID in one write over a full 8-entry list exceeds the
      // 1000-expression budget and is denied (fails closed). The app writes
      // one document per update, which is covered by the 8-entry cases above.
      deny("photo + ID in one write over 8 entries (budget, fails closed)", async () => {
        await seed(path, {...BASE, documents: EIGHT});
        const docs = [...EIGHT.slice(2)].reverse();
        docs.push({...EIGHT[1], documentStatus: "pending", documentURL: "f9", secondaryURL: "b9"});
        docs.push({...EIGHT[0], documentStatus: "pending", documentURL: "p9"});
        return {documents: docs, profileImageUrl: "p9", personalPhotoURL: "p9",
          nationalIdFrontUrl: "f9", nationalIdBackUrl: "b9", updatedAt: "t"};
      });
    });
  }
  test("ALLOW photo removal with FieldValue.delete()", async () => {
    const {deleteField} = require("firebase/firestore");
    await ok(updateDoc(doc(del(), ALL.nested), {profileImageUrl: deleteField(), photoURL: deleteField()}));
  });

  for (const [label, path] of Object.entries({
    nested: "organizations/o1/companies/c1/delegates/sup", top: "delegates/sup", branch: "branches/x1/delegates/sup"})) {
    describe(`M1 no self-approval (${label})`, () => {
      test("DENY supervisor approves own documents", async () => {
        await seed(path, {...PEND, uid: "sup"}); await no(updateDoc(doc(as("sup"), path), APPROVE));
      });
      test("DENY super-admin approves own documents", async () => {
        const p = path.replace(/sup$/, "sa");
        await seed(p, {...PEND, uid: "sa"}); await no(updateDoc(doc(as("sa"), p), APPROVE));
      });
      test("DENY supervisor edits own name directly (M-1)", async () => {
        await seed(path, {...PEND, uid: "sup"}); await no(updateDoc(doc(as("sup"), path), {fullName: "me"}));
      });
      test("ALLOW another same-company approver approves it", async () => {
        await seed(path, {...PEND, uid: "sup"}); await ok(updateDoc(doc(as("ca"), path), APPROVE));
      });
    });
  }

  for (const [label, path] of Object.entries(ALL)) {
    describe(`H1 (a) tech support signup only (${label})`, () => {
      const ta60Nested = TA60_UNBATCHED_STAFF_COMPAT && label === "nested";
      const skipTa60Top = () => TA60_UNBATCHED_STAFF_COMPAT && label !== "nested";
      const provisionCreatePath = ta60Nested
        ? "organizations/o1/companies/c1/delegates/newT"
        : path.replace(/d1$/, "newT");
      const pendDocs = [{...PHOTO, documentStatus: "pending", documentURL: "pX"}];
      const appr = [{...pendDocs[0], documentStatus: "approved"}];
      test("ALLOW ts 'pending' -> 'active' + approve docs batched with the request approval [r4]", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await seed("delegate_requests/d1", {...REQ, profileImageUrl: "pX"});
        await ok(batchApprove(as("ts"), "d1", path, {status: "active", documents: appr}));
      });
      test("ALLOW ts 'pending' -> 'active' without docs change, batched [r4]", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await ok(batchApprove(as("ts"), "d1", path, {status: "active"}));
      });
      test("DENY ts 'pending' -> 'active' + approve docs NOT batched [r4 F2]", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await seed("delegate_requests/d1", {...REQ, profileImageUrl: "pX"});
        await compatNo(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
      });
      test("DENY ts 'pending' -> 'active' NOT batched [r4 F2]", async () => {
        if (skipTa60Top()) return;
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await compatNo(updateDoc(doc(as("ts"), path), {status: "active"}));
      });
      // Mohamed 2026-11-10: tech may activate/reactivate (status-only).
      // Document approval in the same write is still denied outside the
      // request-approval batch. Pending -> active (any case) still requires
      // the batch (techSignup).
      for (const st of ["suspended", "Active", "inactive", "rejected"]) {
        test(`DENY ts '${st}' -> active + approve`, async () => {
          await seed(path, {...BASE, status: st, documents: pendDocs});
          await no(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
        });
        test(`ALLOW ts '${st}' -> active (status-only)`, async () => {
          await seed(path, {...BASE, status: st, documents: pendDocs});
          await ok(updateDoc(doc(as("ts"), path), {status: "active"}));
        });
      }
      for (const st of ["Pending", "pending"]) {
        test(`DENY ts '${st}' -> active + approve (unbatched signup)`, async () => {
          await seed(path, {...BASE, status: st, documents: pendDocs});
          await no(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
        });
        test(`DENY ts '${st}' -> active (unbatched signup)`, async () => {
          if (skipTa60Top()) return;
          await seed(path, {...BASE, status: st, documents: pendDocs});
          await compatNo(updateDoc(doc(as("ts"), path), {status: "active"}));
        });
      }
      test("DENY ts 'pending' -> 'Active' (capital, unbatched signup)", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await compatNo(updateDoc(doc(as("ts"), path), {status: "Active", documents: appr}));
      });
      test("DENY ts missing status -> active + approve", async () => {
        const {status: _s, ...noStatus} = BASE;
        await seed(path, {...noStatus, documents: pendDocs});
        await no(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
      });
      test("ALLOW ts missing status -> active (status-only)", async () => {
        const {status: _s, ...noStatus} = BASE;
        await seed(path, {...noStatus, documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {status: "active"}));
      });
      test("DENY ts approves re-uploaded doc on an active delegate", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await no(updateDoc(doc(as("ts"), path), {documents: appr}));
      });
      test("DENY ts suspend then re-activate + approve (two-step)", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {status: "suspended"}));
        await no(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
      });
      test("ALLOW ts suspend then re-activate status-only (two-step)", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {status: "suspended"}));
        await ok(updateDoc(doc(as("ts"), path), {status: "active"}));
      });
      test("DENY ts approves docs on a pending delegate without activating", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await no(updateDoc(doc(as("ts"), path), {documents: appr}));
      });
      for (const w of ["ts", "hr", "oa", "acc", "sup2", "sup", "ca", "adm"]) {
        test(`DENY ${w} sets status 'pending' on suspended delegate (lift blocked)`, async () => {
          await seed(path, {...BASE, status: "suspended", documents: pendDocs});
          await no(updateDoc(doc(as(w), path), {status: "pending"}));
        });
      }
      test("ALLOW super-admin sets suspended to pending (status-only)", async () => {
        await seed(path, {...BASE, status: "suspended", documents: pendDocs});
        await ok(updateDoc(doc(as("sa"), path), {status: "pending"}));
      });
      test("ALLOW same-company sup approves re-upload on active delegate", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await ok(updateDoc(doc(as("sup"), path), {documents: appr}));
      });
      test("ALLOW ts plain edit / suspend", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {fullName: "z", status: "suspended"}));
      });
      const cpath = provisionCreatePath;
      // r5: a tech approval needs the request's own nested doc
      // (organizations/{org}/companies/{comp}/delegates/{id}) active in the
      // batch, so the same batch on a top-level / branch path is denied.
      const nestedOnly = label === "nested";
      test(`${nestedOnly ? "ALLOW" : "DENY"} ts creates active delegate with approved docs batched with its pending request [r4/r5]`, async () => {
        await seed("delegate_requests/newT", REQ);
        const p = batchApprove(as("ts"), "newT", cpath, {...BASE, uid: "newT", status: "active", documents: [PHOTO]}, true);
        await (nestedOnly || TA60_UNBATCHED_STAFF_COMPAT ? ok(p) : no(p));
      });
      test("DENY ts creates active delegate for an already-approved request (not batched) [r4 F2]", async () => {
        if (skipTa60Top()) return;
        await seed("delegate_requests/newT", {...REQ, status: "approved"});
        await compatNo(setDoc(doc(as("ts"), cpath), {...BASE, uid: "newT", status: "active", documents: [PHOTO]}));
      });
      test("DENY ts creates an active delegate without a signup request", async () => {
        if (skipTa60Top()) return;
        await compatNo(setDoc(doc(as("ts"), cpath), {...BASE, uid: "newT", status: "active", documents: pendDocs}));
      });
      test("DENY ts creates approved-docs delegate when the request is rejected", async () => {
        await seed("delegate_requests/newT", {status: "rejected", organizationUID: "o1", companyUID: "c1"});
        await no(setDoc(doc(as("ts"), cpath), {...BASE, uid: "newT", status: "pending", documents: [PHOTO]}));
      });
      test("ALLOW super-admin creates active delegate with approved docs", () =>
        ok(setDoc(doc(as("sa"), cpath), {...BASE, uid: "newT", status: "active", documents: [PHOTO]})));
    });
  }
  describe("H1 (a) delegate_requests", () => {
    const R = "delegate_requests/d1";
    test("ALLOW ts approves a pending signup request", () =>
      ok(updateDoc(doc(as("ts"), R), {status: "approved", reviewedBy: "ts"})));
    for (const st of ["rejected", "Pending", "approved_x"]) {
      test(`DENY ts approves a '${st}' request`, async () => {
        await seed(R, {status: st, organizationUID: "o1", companyUID: "c1"});
        await no(updateDoc(doc(as("ts"), R), {status: "approved", reviewedBy: "ts"}));
      });
    }
    test("DENY ts approves a request with no status", async () => {
      await seed(R, {organizationUID: "o1", companyUID: "c1"});
      await no(updateDoc(doc(as("ts"), R), {status: "approved"}));
    });
    test("DENY ts moves a rejected request back to 'pending'", async () => {
      await seed(R, {status: "rejected", organizationUID: "o1", companyUID: "c1"});
      await no(updateDoc(doc(as("ts"), R), {status: "pending"}));
    });
    test("ALLOW ts rejects a pending request", () =>
      ok(updateDoc(doc(as("ts"), R), {status: "rejected", rejectionReason: "x"})));
    test("DENY ts other request edit [r4 F1]", () => no(updateDoc(doc(as("ts"), R), {notes: "x"})));
    test("ALLOW ts review fields edit", () => ok(updateDoc(doc(as("ts"), R), {reviewedAt: "t", updatedAt: "t"})));
    test("ALLOW super-admin approves a rejected request", async () => {
      await seed(R, {status: "rejected", organizationUID: "o1", companyUID: "c1"});
      await ok(updateDoc(doc(as("sa"), R), {status: "approved", reviewedBy: "sa"}));
    });
  });

  describe("r4 F1 request create / review", () => {
    const NEW = (sup) => ({...REQ, supervisorUid: sup});
    for (const w of ["ca", "adm", "sup", "oa", "hr"]) {
      test(`ALLOW ${w} creates a request naming itself`, () => ok(setDoc(doc(as(w), "delegate_requests/n1"), NEW(w))));
      test(`DENY ${w} creates a request naming another supervisor`, () => no(setDoc(doc(as(w), "delegate_requests/n1"), NEW("sup2"))));
    }
    test("ALLOW sa creates a request for any supervisor", () => ok(setDoc(doc(as("sa"), "delegate_requests/n1"), NEW("sup"))));
    test("DENY ts creates a request (even naming itself)", () => no(setDoc(doc(as("ts"), "delegate_requests/n1"), NEW("ts"))));
    test("DENY org-admin creates a request whose secondaries include another org", () =>
      no(setDoc(doc(as("oa"), "delegate_requests/oa-multi"), {
        ...NEW("oa"), organizationUIDs: ["o1", "o2"],
      })));
    test("ALLOW org-admin creates a request whose organizationUIDs is only their org", () =>
      ok(setDoc(doc(as("oa"), "delegate_requests/oa-own"), {
        ...NEW("oa"), organizationUIDs: ["o1"],
      })));
    test("ALLOW supervisor creates a request spanning two orgs of the same company", () =>
      ok(setDoc(doc(as("sup"), "delegate_requests/sup-multi"), {
        ...NEW("sup"), organizationUIDs: ["o1", "o2"],
      })));
    test("DENY company staff squats a request id reserved by another company", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("storage_upload_intents/squat1").set({
          companyUID: "c9", createdBy: "callable",
        });
      });
      await no(setDoc(doc(as("ca"), "delegate_requests/squat1"), NEW("ca")));
    });
    test("ALLOW company staff creates on an id reserved by their own company", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("storage_upload_intents/own1").set({
          companyUID: "c1", createdBy: "callable",
        });
      });
      await ok(setDoc(doc(as("ca"), "delegate_requests/own1"), NEW("ca")));
    });
    test("DENY delegate / acc creates a request", async () => {
      await no(setDoc(doc(as("d1"), "delegate_requests/n1"), NEW("d1")));
      await no(setDoc(doc(as("acc"), "delegate_requests/n1"), NEW("acc")));
    });
    test("DENY ts approves a request it supervises", async () => {
      await seed("delegate_requests/n1", NEW("ts"));
      await no(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "approved"}));
    });
    test("DENY ts approves a request it created", async () => {
      await seed("delegate_requests/n1", {...REQ, createdBy: "ts"});
      await no(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "approved"}));
    });
    test("DENY ts edits request URLs / name while approving", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "approved", profileImageUrl: "evil"}));
      await no(updateDoc(doc(as("ts"), "delegate_requests/n1"), {fullName: "x"}));
    });
  });

  describe("r4 F2 batch atomicity", () => {
    const NP = "organizations/o1/companies/c1/delegates/n1";
    test("DENY + request stays pending: ts batch fails partway (bad delegate write)", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", fullName: "Other", status: "active", documents: [PHOTO]}, true));
      assert.equal(await readReq("n1"), "pending");
    });
    test("DENY + request stays pending: super-admin batch fails partway (device binding on create)", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("sa"), "n1", NP, {...BASE, uid: "n1", status: "active", boundDeviceId: "dev1", documents: [PHOTO]}, true));
      assert.equal(await readReq("n1"), "pending");
    });
    test("ALLOW super-admin uses the same batch", async () => {
      await seed("delegate_requests/n1", REQ);
      await ok(batchApprove(as("sa"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [PHOTO]}, true));
      assert.equal(await readReq("n1"), "approved");
    });
    test("DENY ts approves the request first, then activates in a later write", async () => {
      await seed("delegate_requests/n1", REQ);
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: [{...PHOTO, documentStatus: "pending"}]});
      // r5: the lone request approval (old builds' first step) is denied too.
      await compatNo(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "approved"}));
      if (!TA60_UNBATCHED_STAFF_COMPAT) assert.equal(await readReq("n1"), "pending");
      await compatNo(updateDoc(doc(as("ts"), NP), {status: "active", documents: [PHOTO]}));
    });
    test("DENY ts batch whose request is rejected in the same batch", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [PHOTO]}, true, {status: "rejected"}));
    });
  });

  describe("r4 F3 path / URL binding", () => {
    const NP = "organizations/o1/companies/c1/delegates/n1";
    test("DENY ts batch into a company other than the request's", async () => {
      await seed("delegate_requests/n1", {...REQ, companyUID: "c2"});
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [PHOTO]}, true));
    });
    test("DENY ts batch with companyUID field != path", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", companyUID: "c2", status: "active", documents: [PHOTO]}, true));
    });
    test("DENY ts approved photo URL differs from the request", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [{...PHOTO, documentURL: "evil"}]}, true));
    });
    test("DENY ts approved ID back differs from the request", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [{...NID, secondaryURL: "evil"}]}, true));
    });
    test("DENY ts approved unknown key", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active",
        documents: [{documentKey: "healthCertificate", documentStatus: "approved", documentURL: "h"}]}, true));
    });
    test("ALLOW ts batch with photo + ID + receipt from the request", async () => {
      await seed("delegate_requests/n1", REQ);
      await ok(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [PHOTO, NID, RCPT]}, true));
    });
    test("ALLOW ts new_delegate copy under the supervisor's organization (2e)", async () => {
      await seed("users/supX", {role: "supervisor", organizationUID: "o9", companyUID: "c1"});
      await seed("organizations/o9/companies/c1", {name: "C1", organizationUID: "o9"});
      await seed("delegate_requests/n1", {...REQ, supervisorUid: "supX"});
      const db = as("ts");
      const bb = writeBatch(db);
      bb.update(doc(db, "delegate_requests/n1"), {status: "approved"});
      bb.set(doc(db, NP), {...BASE, uid: "n1", status: "active", documents: [PHOTO]});
      bb.set(doc(db, "organizations/o9/companies/c1/delegates/n1"), {...BASE, uid: "n1", organizationUID: "o9", status: "active", documents: [PHOTO]});
      await ok(bb.commit());
    });
    test("DENY ts copy under an unrelated organization", async () => {
      await seed("delegate_requests/n1", REQ);
      await no(batchApprove(as("ts"), "n1", "organizations/o7/companies/c1/delegates/n1",
        {...BASE, uid: "n1", organizationUID: "o7", status: "active", documents: [PHOTO]}, true));
    });
  });

  describe("r4 F4 status-only activation", () => {
    const NP = "organizations/o1/companies/c1/delegates/n1";
    const P = {...PHOTO, documentStatus: "pending"};
    const seedP = async (extra = {}) => {
      await seed("delegate_requests/n1", REQ);
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: [P, {...NID, documentStatus: "pending"}], ...extra});
    };
    const flip = [{...PHOTO, reviewedBy: "ts"}, NID];
    test("ALLOW ts flips pending -> approved by index", async () => {
      await seedP();
      await ok(batchApprove(as("ts"), "n1", NP, {status: "active", documents: flip, reviewedBy: "ts", updatedAt: "t"}));
    });
    test("DENY ts activation that also edits the name", async () => {
      await seedP();
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: flip, fullName: "x"}));
    });
    test("DENY ts activation that changes a URL field", async () => {
      await seedP();
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: flip, profileImageUrl: "p1"}));
    });
    test("DENY ts activation that grows the documents list", async () => {
      await seedP();
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: [...flip, {...RCPT, documentStatus: "pending"}]}));
    });
    test("DENY ts activation that shrinks the documents list", async () => {
      await seedP();
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: [flip[0]]}));
    });
    test("DENY ts flip that changes the entry URL", async () => {
      await seedP();
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: [{...PHOTO, documentURL: "p9"}, NID]}));
    });
    test("DENY ts flip that changes another entry field", async () => {
      await seedP();
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: [{...PHOTO, uploadedAt: "x"}, NID]}));
    });
    test("DENY ts activation of a doc marked statusReason 'delete'", async () => {
      await seedP({statusReason: "delete"});
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: flip}));
    });
  });

  describe("r4 R2 add_organization (tech approves, Q4)", () => {
    const AP = "organizations/o2/companies/c1/delegates/d1";
    const AREQ = {...REQ, requestType: "add_organization", existingDelegateUid: "d1", organizationUID: "o2"};
    const D = {...BASE, organizationUID: "o2", status: "active", approvedRequestId: "a1", documents: [PHOTO, NID, RCPT]};
    test("ALLOW ts creates the add_org doc batched with its request", async () => {
      await seed("delegate_requests/a1", AREQ);
      await ok(batchApprove(as("ts"), "a1", AP, D, true));
    });
    test("ALLOW ts add_org batch that heals request nationalId to the created doc ID", async () => {
      await seed("delegate_requests/a1", {...AREQ, nationalId: "11111111111111", nationalityID: "11111111111111"});
      await ok(batchApprove(as("ts"), "a1", AP, {...D, nationalId: "29901010101011", nationalityID: "29901010101011"}, true, {
        nationalId: "29901010101011", nationalityID: "29901010101011",
      }));
    });
    test("DENY ts add_org batch that writes a nationalId different from the created doc", async () => {
      await seed("delegate_requests/a1", {...AREQ, nationalId: "11111111111111", nationalityID: "11111111111111"});
      await no(batchApprove(as("ts"), "a1", AP, {...D, nationalId: "29901010101011", nationalityID: "29901010101011"}, true, {
        nationalId: "28801010101011", nationalityID: "28801010101011",
      }));
    });
    test("DENY ts add_org without approvedRequestId", async () => {
      await seed("delegate_requests/a1", AREQ);
      const {approvedRequestId: _x, ...noId} = D;
      await no(batchApprove(as("ts"), "a1", AP, noId, true));
    });
    test("DENY ts add_org for a different delegate", async () => {
      await seed("delegate_requests/a1", {...AREQ, existingDelegateUid: "other"});
      await no(batchApprove(as("ts"), "a1", AP, D, true));
    });
    test("DENY ts add_org not batched", async () => {
      await seed("delegate_requests/a1", AREQ);
      await compatNo(setDoc(doc(as("ts"), AP), D));
    });
    test("DENY ts add_org into another organization", async () => {
      await seed("delegate_requests/a1", AREQ);
      await no(batchApprove(as("ts"), "a1", "organizations/o3/companies/c1/delegates/d1", {...D, organizationUID: "o3"}, true));
    });
  });

  describe("r5 old builds: tech approval needs the target active in the same batch", () => {
    const NP = "organizations/o1/companies/c1/delegates/n1";
    const AP = "organizations/o2/companies/c1/delegates/d1";
    const AREQ = {...REQ, requestType: "add_organization", existingDelegateUid: "d1", organizationUID: "o2"};
    test("DENY ts approves new_delegate alone (no delegate doc)", async () => {
      await seed("delegate_requests/n1", REQ);
      await compatNo(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "approved", reviewedBy: "ts"}));
      if (!TA60_UNBATCHED_STAFF_COMPAT) assert.equal(await readReq("n1"), "pending");
    });
    test("DENY ts approves new_delegate alone (delegate doc still pending)", async () => {
      await seed("delegate_requests/n1", REQ);
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: [{...PHOTO, documentStatus: "pending"}]});
      await compatNo(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "approved", reviewedBy: "ts"}));
    });
    test("DENY ts approves add_organization alone", async () => {
      await seed("delegate_requests/a1", AREQ);
      await compatNo(updateDoc(doc(as("ts"), "delegate_requests/a1"), {status: "approved", reviewedBy: "ts"}));
      if (!TA60_UNBATCHED_STAFF_COMPAT) assert.equal(await readReq("a1"), "pending");
    });
    test("DENY ts approves add_organization with no existingDelegateUid", async () => {
      await seed("delegate_requests/a1", {...AREQ, existingDelegateUid: null});
      await no(updateDoc(doc(as("ts"), "delegate_requests/a1"), {status: "approved"}));
    });
    test("ALLOW ts approves delete_delegate alone (Q3 unchanged)", async () => {
      await seed("delegate_requests/x1", {...REQ, requestType: "delete_delegate"});
      await ok(updateDoc(doc(as("ts"), "delegate_requests/x1"), {status: "approved", reviewedBy: "ts"}));
    });
    test("ALLOW ts rejects new_delegate alone", async () => {
      await seed("delegate_requests/n1", REQ);
      await ok(updateDoc(doc(as("ts"), "delegate_requests/n1"), {status: "rejected", rejectionReason: "x"}));
    });
    test("ALLOW super-admin approves new_delegate alone (unchanged)", async () => {
      await seed("delegate_requests/n1", REQ);
      await ok(updateDoc(doc(as("sa"), "delegate_requests/n1"), {status: "approved", reviewedBy: "sa"}));
    });
    test("ALLOW ts batched create (new_delegate) still passes", async () => {
      await seed("delegate_requests/n1", REQ);
      await ok(batchApprove(as("ts"), "n1", NP, {...BASE, uid: "n1", status: "active", documents: [PHOTO, NID, RCPT]}, true));
    });
    test("ALLOW ts batched add_organization still passes", async () => {
      await seed("delegate_requests/a1", AREQ);
      await ok(batchApprove(as("ts"), "a1", AP, {...BASE, organizationUID: "o2", status: "active", approvedRequestId: "a1", documents: [PHOTO, NID, RCPT]}, true));
    });
  });

  describe("r5 budget: tech status-only activation with an extra pending e-receipt", () => {
    const NP = "organizations/o1/companies/c1/delegates/n1";
    const ER = {documentKey: "electronicPaymentReceipt", documentStatus: "approved", documentURL: "r0"};
    const ER2 = {documentKey: "electronic_payment_receipt", documentStatus: "approved", documentURL: "r0"};
    const pend = (e) => ({...e, documentStatus: "pending"});
    const extra = (i) => ({documentKey: "x" + i, documentStatus: "pending", documentURL: "x"});
    test("ALLOW 4 flips (photo, ID, receipt, e-receipt) + 4 untouched entries", async () => {
      await seed("delegate_requests/n1", REQ);
      const o = [pend(PHOTO), pend(NID), pend(RCPT), pend(ER), extra(1), extra(2), extra(3), extra(4)];
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: o});
      const n = o.map((e, i) => (i < 4 ? {...e, documentStatus: "approved"} : e));
      await ok(batchApprove(as("ts"), "n1", NP, {status: "active", documents: n, reviewedBy: "ts", updatedAt: "t"}));
      assert.equal(await readReq("n1"), "approved");
    });
    test("DENY (documented limit) 5 flips on one doc: atomic, request stays pending", async () => {
      await seed("delegate_requests/n1", REQ);
      const o = [pend(PHOTO), pend(NID), pend(RCPT), pend(ER), pend(ER2)];
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: o});
      const n = o.map((e) => ({...e, documentStatus: "approved"}));
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: n}));
      assert.equal(await readReq("n1"), "pending");
    });
    test("ALLOW super-admin 5 flips on one doc", async () => {
      await seed("delegate_requests/n1", REQ);
      const o = [pend(PHOTO), pend(NID), pend(RCPT), pend(ER), pend(ER2)];
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: o});
      const n = o.map((e) => ({...e, documentStatus: "approved"}));
      await ok(batchApprove(as("sa"), "n1", NP, {status: "active", documents: n}));
    });
    test("DENY ts flip with a mismatched e-receipt URL", async () => {
      await seed("delegate_requests/n1", REQ);
      const o = [pend(PHOTO), pend(NID), pend(RCPT), {...pend(ER), documentURL: "evil"}];
      await seed(NP, {...BASE, uid: "n1", status: "pending", documents: o});
      const n = o.map((e) => ({...e, documentStatus: "approved"}));
      await no(batchApprove(as("ts"), "n1", NP, {status: "active", documents: n}));
    });
  });

  describe("r5 tech create binds phone and top-level URLs", () => {
    const NP = "organizations/o1/companies/c1/delegates/n1";
    const R = {...REQ, phoneNumber: "0100000000"};
    const D = {...BASE, uid: "n1", phoneNumber: "0100000000", status: "active", documents: [PHOTO, NID, RCPT]};
    test("ALLOW the app's create payload", async () => {
      await seed("delegate_requests/n1", R);
      await ok(batchApprove(as("ts"), "n1", NP, D, true));
    });
    for (const [k, v] of [["phoneNumber", "0199999999"], ["nationalIdFrontUrl", "evil"], ["nationalIdBackUrl", "evil"],
      ["receiptImageUrl", "evil"], ["personalPhotoURL", "evil"], ["photoURL", "evil"]]) {
      test(`DENY ts create with a different ${k}`, async () => {
        await seed("delegate_requests/n1", R);
        await compatNo(batchApprove(as("ts"), "n1", NP, {...D, [k]: v}, true));
        if (!TA60_UNBATCHED_STAFF_COMPAT) assert.equal(await readReq("n1"), "pending");
      });
    }
  });

  describe("r5 sent_notifications log (app payload: senderUid, no supervisorUid)", () => {
    const SN = (w) => ({title: "t", body: "b", senderUid: w, senderName: "S", targetType: "company",
      organizationUID: "o1", companyUID: "c1", sentAt: "t", recipientCount: 3});
    for (const w of ["sa", "ts", "oa", "ca", "adm", "sup", "hr"]) {
      test(`ALLOW ${w} writes the notification log`, () => ok(setDoc(doc(as(w), `sent_notifications/s_${w}`), SN(w))));
    }
    for (const w of ["acc", "bmm", "mk", "d1"]) {
      test(`DENY ${w} writes the notification log`, () => no(setDoc(doc(as(w), `sent_notifications/s_${w}`), SN(w))));
    }
  });

  describe("Q3 who can delete", () => {
    const NP = "organizations/o1/companies/c1/delegates/d1";
    for (const w of ["sa", "ts", "oa", "mk", "ca", "adm", "sup", "hr"]) {
      test(`ALLOW ${w} deletes a nested delegate (same org/company)`, () => ok(deleteDoc(doc(as(w), NP))));
    }
    // acc / bmm: pre-existing (unchanged by r4) delete rules hit the
    // 1000-expression limit for these roles and fail closed.
    for (const w of ["sup2", "d1", "acc", "bmm"]) {
      test(`DENY ${w} deletes a nested delegate`, () => no(deleteDoc(doc(as(w), NP))));
    }
    test("ALLOW ts approves a pending delete_delegate request (Q3)", async () => {
      await seed("delegate_requests/x1", {...REQ, requestType: "delete_delegate", existingDelegateUid: "d1"});
      await ok(updateDoc(doc(as("ts"), "delegate_requests/x1"), {status: "approved", reviewedBy: "ts"}));
    });
    for (const w of ["sa", "oa"]) {
      test(`ALLOW ${w} deletes a request doc`, () => ok(deleteDoc(doc(as(w), "delegate_requests/d1"))));
    }
    for (const w of ["ts", "ca", "sup", "d1"]) {
      test(`DENY ${w} deletes a request doc`, () => no(deleteDoc(doc(as(w), "delegate_requests/d1"))));
    }
  });

  describe("L1 documentStatus type / L2 unchanged unknown keys", () => {
    const p = ALL.nested;
    for (const [n, v] of [["number", 1], ["map", {a: 1}], ["bool", true]]) {
      test(`DENY new entry with ${n} documentStatus`, () =>
        no(updateDoc(doc(del(), p), {documents: [{...PHOTO, documentStatus: v, documentURL: "p1"}, NID, RCPT], profileImageUrl: "p1"})));
    }
    test("ALLOW unchanged legacy entry with odd status type carried over", async () => {
      const odd = {documentKey: "healthCertificate", documentStatus: 3, documentURL: "h"};
      await seed(p, {...BASE, documents: [...BASE.documents, odd]});
      await ok(updateDoc(doc(del(), p), {documents: [{...PHOTO, documentStatus: "pending", documentURL: "p1"}, NID, RCPT, odd], profileImageUrl: "p1"}));
    });
    test("ALLOW legacy approved unknown-key entry carried over during re-upload", async () => {
      const leg = {documentKey: "personal_photo", documentStatus: "approved", documentURL: "L"};
      await seed(p, {...BASE, documents: [...BASE.documents, leg]});
      await ok(updateDoc(doc(del(), p), {documents: [{...PHOTO, documentStatus: "pending", documentURL: "p1"}, NID, RCPT, leg], profileImageUrl: "p1"}));
    });
    test("DENY new approved unknown key", () =>
      no(updateDoc(doc(del(), p), {documents: [PHOTO, NID, RCPT, {documentKey: "bogus", documentStatus: "approved", documentURL: "z"}]})));
    test("DENY copy approved entry under another key", () =>
      no(updateDoc(doc(del(), p), {documents: [PHOTO, NID, RCPT, {...PHOTO, documentKey: "healthCertificate"}]})));
    test("ALLOW pending unknown key", () =>
      ok(updateDoc(doc(del(), p), {documents: [PHOTO, NID, RCPT, {documentKey: "bogus", documentStatus: "pending", documentURL: "z"}]})));
  });
});
