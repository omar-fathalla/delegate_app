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
    test("ALLOW tech support signup approval (pending -> active with approved docs) [H1a]", () =>
      assertSucceeds(updateDoc(doc(as("ts"), pendPath), {...approveData, status: "active"})));
    test("ALLOW super-admin signup approval (pending -> active with approved docs)", () =>
      assertSucceeds(updateDoc(doc(as("sa"), pendPath), {...approveData, status: "active"})));
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
    test("DENY delegate updates profileImageUrl without a pending entry (L4)", () => assertFails(updateDoc(doc(del(), p), {profileImageUrl: "p1", updatedAt: "t"})));
    test("ALLOW delegate removes profileImageUrl", () => assertSucceeds(updateDoc(doc(del(), p), {profileImageUrl: "", updatedAt: "t"})));
    test("ALLOW delegate re-upload as pending", () => assertSucceeds(updateDoc(doc(del(), p),
      {documents: [{...PHOTO, documentURL: "p1", documentStatus: "pending"}], profileImageUrl: "p1", updatedAt: "t"})));
    test("ALLOW company staff review update", () => assertSucceeds(updateDoc(doc(as("sup"), p), {status: "approved", reviewedBy: "s"})));
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
      for (const p of Object.values(ALL)) await db.doc(p).set(BASE);
      await db.doc("delegate_requests/d1").set({
        status: "pending", organizationUID: "o1", companyUID: "c1", profileImageUrl: "p0",
        nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", documents: BASE.documents});
    });
  });

  for (const [label, path] of Object.entries({top: ALL.top, branch: ALL.branch})) {
    describe(`B1 staff on group path (${label})`, () => {
      for (const w of ["sa", "ca", "sup", "hr", "ts"]) {
        test(`ALLOW ${w} plain edit (no emulator error)`, () => ok(updateDoc(doc(as(w), path), {fullName: "z"})));
      }
      for (const w of ["sa", "ca", "adm", "sup"]) {
        test(`ALLOW ${w} approves pending entry`, async () => {
          await seed(path, PEND); await ok(updateDoc(doc(as(w), path), APPROVE));
        });
      }
      for (const w of ["sup2", "hr", "acc", "ts"]) {
        test(`DENY ${w} approves pending entry`, async () => {
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
      test("ALLOW supervisor edits own name", async () => {
        await seed(path, {...PEND, uid: "sup"}); await ok(updateDoc(doc(as("sup"), path), {fullName: "me"}));
      });
      test("ALLOW another same-company approver approves it", async () => {
        await seed(path, {...PEND, uid: "sup"}); await ok(updateDoc(doc(as("ca"), path), APPROVE));
      });
    });
  }

  for (const [label, path] of Object.entries(ALL)) {
    describe(`H1 (a) tech support signup only (${label})`, () => {
      const pendDocs = [{...PHOTO, documentStatus: "pending", documentURL: "pX"}];
      const appr = [{...pendDocs[0], documentStatus: "approved"}];
      test("ALLOW ts 'pending' -> 'active' + approve docs in the same write", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
      });
      test("ALLOW ts 'pending' -> 'active' without docs change", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {status: "active"}));
      });
      for (const st of ["suspended", "Active", "inactive", "Pending", "rejected"]) {
        test(`DENY ts '${st}' -> active + approve`, async () => {
          await seed(path, {...BASE, status: st, documents: pendDocs});
          await no(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
        });
        test(`DENY ts '${st}' -> active`, async () => {
          await seed(path, {...BASE, status: st, documents: pendDocs});
          await no(updateDoc(doc(as("ts"), path), {status: "active"}));
        });
      }
      test("DENY ts 'pending' -> 'Active' (capital)", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await no(updateDoc(doc(as("ts"), path), {status: "Active", documents: appr}));
      });
      test("DENY ts missing status -> active + approve", async () => {
        const {status: _s, ...noStatus} = BASE;
        await seed(path, {...noStatus, documents: pendDocs});
        await no(updateDoc(doc(as("ts"), path), {status: "active", documents: appr}));
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
      test("DENY ts approves docs on a pending delegate without activating", async () => {
        await seed(path, {...BASE, status: "pending", documents: pendDocs});
        await no(updateDoc(doc(as("ts"), path), {documents: appr}));
      });
      for (const w of ["ts", "hr", "oa", "acc", "sup2"]) {
        test(`DENY non-approver ${w} sets status 'pending' on an existing doc`, async () => {
          await seed(path, {...BASE, status: "suspended", documents: pendDocs});
          await no(updateDoc(doc(as(w), path), {status: "pending"}));
        });
      }
      for (const w of ["sa", "sup"]) {
        test(`ALLOW approver ${w} sets status 'pending'`, async () => {
          await seed(path, {...BASE, status: "suspended", documents: pendDocs});
          await ok(updateDoc(doc(as(w), path), {status: "pending"}));
        });
      }
      test("ALLOW same-company sup approves re-upload on active delegate", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await ok(updateDoc(doc(as("sup"), path), {documents: appr}));
      });
      test("ALLOW ts plain edit / suspend", async () => {
        await seed(path, {...BASE, documents: pendDocs});
        await ok(updateDoc(doc(as("ts"), path), {fullName: "z", status: "suspended"}));
      });
      const cpath = path.replace(/d1$/, "newT");
      test("ALLOW ts creates active delegate with approved docs for a pending/approved signup request", async () => {
        await seed("delegate_requests/newT", {status: "approved", organizationUID: "o1", companyUID: "c1"});
        await ok(setDoc(doc(as("ts"), cpath), {...BASE, uid: "newT", status: "active", documents: [PHOTO]}));
      });
      test("DENY ts creates an active delegate without a signup request", () =>
        no(setDoc(doc(as("ts"), cpath), {...BASE, uid: "newT", status: "active", documents: pendDocs})));
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
    test("ALLOW ts other request edit", () => ok(updateDoc(doc(as("ts"), R), {notes: "x"})));
    test("ALLOW super-admin approves a rejected request", async () => {
      await seed(R, {status: "rejected", organizationUID: "o1", companyUID: "c1"});
      await ok(updateDoc(doc(as("sa"), R), {status: "approved", reviewedBy: "sa"}));
    });
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
