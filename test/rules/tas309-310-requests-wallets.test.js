/**
 * TAS-309: company requests (organizations/{org}/companies/{co}/requests)
 *   only approvers (super-admin / technical support, or the organization admin
 *   of that organization) set approved / rejected / action_required. Company
 *   staff create 'pending', cancel, resubmit to 'pending', or edit without a
 *   status change.
 * TAS-310: organization admins no longer write user_wallets or their
 *   transactions (no company / chain check existed).
 *
 * Fake data only. npm run test:rules:tas309-310
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertDeniedByRule,
} = require("./_rules_testing");
const {doc, setDoc, updateDoc, Timestamp} = require("firebase/firestore");

const ORG_A = "seed-fake-tas309-org-a";
const ORG_B = "seed-fake-tas309-org-b";
const CO_A = "seed-fake-tas309-co-a";
const CO_B = "seed-fake-tas309-co-b";
const since = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));

const users = {
  "sa": {doc: {role: "super-admin"}, claims: {role: "super-admin"}},
  "orgadmin-a": {
    doc: {role: "organization-admin", organizationUID: ORG_A},
    claims: {role: "organization-admin", orgId: ORG_A},
  },
  "orgadmin-b": {
    doc: {role: "organization-admin", organizationUID: ORG_B},
    claims: {role: "organization-admin", orgId: ORG_B},
  },
  "cadmin-a": {
    doc: {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A},
    claims: {role: "company-admin", orgId: ORG_A, companyId: CO_A},
  },
  "hr-a": {doc: {role: "hr", organizationUID: ORG_A, companyUID: CO_A}, claims: {}},
  "acc": {doc: {role: "accountant"}, claims: {role: "accountant"}},
};

let env;
const db = (uid) => env.authenticatedContext(uid, users[uid].claims).firestore();
const reqPath = (id) => `organizations/${ORG_A}/companies/${CO_A}/requests/${id}`;

async function seedRequest(id, status) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), reqPath(id)), {
      uid: id, organizationUID: ORG_A, companyUID: CO_A, status,
      actionType: "new_id", createdAt: since, updatedAt: since, fake: true,
    });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas309",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(fs, `users/${uid}`), {...u.doc, createdAt: since, fake: true});
    }
    for (const [org, co] of [[ORG_A, CO_A], [ORG_B, CO_B]]) {
      await setDoc(doc(fs, `organizations/${org}`), {name: org, fake: true});
      await setDoc(doc(fs, `organizations/${org}/companies/${co}`), {
        name: co, organizationUID: org, status: "active", fake: true,
      });
    }
    await setDoc(doc(fs, "user_wallets/w1"), {companyUID: CO_A, currentBalance: 0, fake: true});
  });
});

after(async () => {
  await env?.cleanup();
});

const newReq = (status) => ({
  organizationUID: ORG_A, companyUID: CO_A, status, actionType: "new_id",
  createdAt: since, updatedAt: since, fake: true,
});

describe("TAS-309 company staff cannot decide requests", () => {
  test("company admin creates a pending request", async () => {
    await assertSucceeds(setDoc(doc(db("cadmin-a"), reqPath("c-pending")), newReq("pending")));
  });
  test("company admin cannot create an approved request", async () => {
    await assertDeniedByRule(setDoc(doc(db("cadmin-a"), reqPath("c-approved")), newReq("approved")));
  });
  for (const decision of ["approved", "rejected", "action_required"]) {
    test(`company admin cannot move pending -> ${decision}`, async () => {
      await seedRequest(`u-${decision}`, "pending");
      await assertDeniedByRule(updateDoc(doc(db("cadmin-a"), reqPath(`u-${decision}`)), {status: decision}));
    });
  }
  test("HR of the company cannot approve", async () => {
    await seedRequest("u-hr", "pending");
    await assertDeniedByRule(updateDoc(doc(db("hr-a"), reqPath("u-hr")), {status: "approved"}));
  });
  test("company admin cancels a pending request", async () => {
    await seedRequest("u-cancel", "pending");
    await assertSucceeds(updateDoc(doc(db("cadmin-a"), reqPath("u-cancel")), {status: "cancelled"}));
  });
  test("company admin resubmits action_required -> pending", async () => {
    await seedRequest("u-resubmit", "action_required");
    await assertSucceeds(updateDoc(doc(db("cadmin-a"), reqPath("u-resubmit")), {status: "pending"}));
  });
  test("company admin edits without changing the status", async () => {
    await seedRequest("u-edit", "pending");
    await assertSucceeds(updateDoc(doc(db("cadmin-a"), reqPath("u-edit")), {note: "fixed"}));
  });
  test("company admin cannot reopen an approved request", async () => {
    await seedRequest("u-reopen", "approved");
    await assertDeniedByRule(updateDoc(doc(db("cadmin-a"), reqPath("u-reopen")), {status: "pending"}));
  });
});

describe("TAS-309 approvers still decide", () => {
  test("organization admin of the organization approves", async () => {
    await seedRequest("a-org", "pending");
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), reqPath("a-org")), {status: "approved"}));
  });
  test("organization admin rejects / requests changes", async () => {
    await seedRequest("a-rej", "pending");
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), reqPath("a-rej")), {status: "rejected"}));
    await seedRequest("a-ar", "pending");
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), reqPath("a-ar")), {status: "action_required"}));
  });
  test("super-admin approves", async () => {
    await seedRequest("a-sa", "pending");
    await assertSucceeds(updateDoc(doc(db("sa"), reqPath("a-sa")), {status: "approved"}));
  });
  test("organization admin of another organization is denied", async () => {
    await seedRequest("a-other", "pending");
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-b"), reqPath("a-other")), {status: "approved"}));
  });
});

describe("TAS-310 wallets", () => {
  test("organization admin cannot update a wallet", async () => {
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), "user_wallets/w1"), {currentBalance: 500}));
  });
  test("organization admin cannot create a wallet", async () => {
    await assertDeniedByRule(setDoc(doc(db("orgadmin-a"), "user_wallets/w-new"), {companyUID: CO_B, currentBalance: 1}));
  });
  test("organization admin cannot write wallet transactions", async () => {
    await assertDeniedByRule(setDoc(doc(db("orgadmin-a"), "user_wallets/w1/transactions/t1"), {amount: 10}));
  });
  test("accountant and super-admin still write", async () => {
    await assertSucceeds(updateDoc(doc(db("acc"), "user_wallets/w1"), {currentBalance: 10}));
    await assertSucceeds(updateDoc(doc(db("sa"), "user_wallets/w1"), {currentBalance: 20}));
    await assertSucceeds(setDoc(doc(db("acc"), "user_wallets/w1/transactions/t2"), {amount: 10}));
  });
});
