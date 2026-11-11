/**
 * Phase 1 item 1: clients cannot set or change delegate source stamps.
 * Emulator only: npm run test:rules:source
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");

const PATH = "organizations/o1/companies/c1/delegates/d1";
const BASE = {
  uid: "d1",
  fullName: "Fake",
  organizationUID: "o1",
  companyUID: "c1",
  status: "active",
  role: "delegate",
  phoneNumber: "01011111111",
};

describe("delegate source stamps are server-only", () => {
  let env;
  // Role claims are required for delegateOwns / isDelegate (users/{uid}
  // is not enough). Without them, a self-update falls through to the
  // staff path and hits the 1000-expression budget.
  const CLAIMS = {
    sa: {role: "super-admin"},
    sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
    d1: {role: "delegate", organizationUID: "o1", companyUID: "c1"},
    ts: {role: "technical_support", organizationUID: "o1"},
  };
  const as = (uid) => env.authenticatedContext(uid, {
    firebase: {sign_in_provider: "password"},
    ...(CLAIMS[uid] || {}),
  }).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-delegate-source",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sa").set({role: "super-admin"});
      await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/d1").set({role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d1"});
      await db.doc("users/ts").set({role: "technical_support", organizationUID: "o1"});
      await db.doc("organizations/o1").set({name: "Org"});
      await db.doc("organizations/o1/companies/c1").set({name: "Co"});
      await db.doc(PATH).set(BASE);
      await db.doc("organizations/o1/companies/c1/delegates/stamped").set({
        ...BASE,
        uid: "stamped",
        delegateSource: "web",
        chainOrigin: "web_request",
        delegateSourceInferredBy: "backfill",
        delegateSourceRunId: "dev-test",
      });
    });
  });

  test("client cannot create a delegate with source stamps", async () => {
    const path = "organizations/o1/companies/c1/delegates/new1";
    await assertFails(as("sa").doc(path).set({...BASE, uid: "new1", delegateSource: "app"}));
    await assertFails(as("sa").doc(path).set({...BASE, uid: "new1", chainOrigin: "app_new_delegate"}));
    await assertFails(as("sup").doc(path).set({
      ...BASE, uid: "new1", delegateSource: "web", chainOrigin: "web_request",
    }));
  });

  test("super-admin can create a delegate without source stamps", async () => {
    await assertSucceeds(as("sa").doc("organizations/o1/companies/c1/delegates/new2").set({
      ...BASE, uid: "new2",
    }));
  });

  test("client cannot change or clear source stamps", async () => {
    const ref = as("sa").doc("organizations/o1/companies/c1/delegates/stamped");
    await assertFails(ref.update({delegateSource: "app"}));
    await assertFails(ref.update({chainOrigin: "unknown"}));
    await assertFails(ref.update({delegateSourceInferredBy: "me"}));
    await assertFails(ref.update({delegateSourceRunId: "hack"}));
    await assertFails(as("sup").doc("organizations/o1/companies/c1/delegates/stamped").update({
      delegateSource: "app",
    }));
  });

  test("a non-source update on a stamped doc is still allowed for super-admin", async () => {
    await assertSucceeds(as("sa").doc("organizations/o1/companies/c1/delegates/stamped").update({
      updatedAt: "t1",
    }));
  });

  test("delegate self-update may change allow-listed fields but not source stamps", async () => {
    const ref = as("d1").doc(PATH);
    await assertSucceeds(ref.update({updatedAt: "t-self"}));
    await assertFails(ref.update({updatedAt: "t-self", delegateSource: "app"}));
    await assertFails(ref.update({delegateSourceRevertRunId: "hack"}));
  });

  test("tech approval (pending → active) cannot write source stamps", async () => {
    const path = "organizations/o1/companies/c1/delegates/dtech";
    const docs = [
      {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "p0"},
      {documentKey: "nationalityId", documentStatus: "pending", documentURL: "f0", secondaryURL: "b0"},
    ];
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/dtech").set({role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "dtech"});
      await db.doc(path).set({
        ...BASE, uid: "dtech", status: "pending",
        profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
        documents: docs,
      });
      await db.doc("delegate_requests/dtech").set({
        requestType: "new_delegate", status: "pending",
        supervisorUid: "sup", organizationUID: "o1", companyUID: "c1",
        profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
        firstName: "Fake", secondName: "T", thirdName: "User",
        fullName: "Fake T User", nationalId: "x",
      });
    });
    const flipped = docs.map((d) => ({...d, documentStatus: "approved", reviewedBy: "TS", reviewedAt: "t"}));
    const ts = as("ts");
    // Request approval + status-only activation in one batch, no source keys.
    const batchOk = ts.batch();
    batchOk.update(ts.doc("delegate_requests/dtech"), {status: "approved", reviewedBy: "TS", reviewedAt: "t"});
    batchOk.update(ts.doc(path), {
      status: "active", documents: flipped, updatedAt: "t",
      reviewedBy: "TS", reviewedAt: "t", approvedRequestId: "dtech",
    });
    await assertSucceeds(batchOk.commit());

    // Same activation but also setting a source stamp must fail.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc(path).set({
        ...BASE, uid: "dtech", status: "pending",
        profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
        documents: docs,
      });
      await db.doc("delegate_requests/dtech").set({
        requestType: "new_delegate", status: "pending",
        supervisorUid: "sup", organizationUID: "o1", companyUID: "c1",
        profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
        firstName: "Fake", secondName: "T", thirdName: "User",
        fullName: "Fake T User", nationalId: "x",
      });
    });
    const batchBad = ts.batch();
    batchBad.update(ts.doc("delegate_requests/dtech"), {status: "approved", reviewedBy: "TS", reviewedAt: "t"});
    batchBad.update(ts.doc(path), {
      status: "active", documents: flipped, updatedAt: "t",
      reviewedBy: "TS", reviewedAt: "t", approvedRequestId: "dtech",
      delegateSource: "web",
    });
    await assertFails(batchBad.commit());
  });

  test("client cannot create a delegate with hold authority fields", async () => {
    const path = "organizations/o1/companies/c1/delegates/new-hold";
    await assertFails(as("sa").doc(path).set({...BASE, uid: "new-hold", holds: {admin_suspend: {at: "x"}}}));
    await assertFails(as("sa").doc(path).set({...BASE, uid: "new-hold", statusVersion: 1}));
    await assertFails(as("sa").doc(path).set({...BASE, uid: "new-hold", rejectionReason: "x"}));
  });

  test("client cannot write hold authority fields", async () => {
    const ref = as("sa").doc(PATH);
    await assertFails(ref.update({holds: {admin_suspend: {at: "x"}}}));
    await assertFails(ref.update({statusVersion: 1}));
    await assertFails(ref.update({holdsAuthorityAt: "x"}));
    await assertFails(ref.update({rejectionReason: "x"}));
    await assertFails(ref.update({holdsBackfillRunId: "run"}));
  });

  test("clients cannot write status_audit or statusHistory", async () => {
    await assertFails(as("sa").doc("status_audit/a1").set({uid: "d1", to: "suspended"}));
    await assertFails(as("sa").doc(PATH + "/statusHistory/h1").set({from: "active", to: "suspended"}));
  });

});
