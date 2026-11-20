// TAS-105 / TAS-106: guards on Firestore's 1000-expression rule budget.
//
// 1. Security-critical denies must come from a rule condition, never from the
//    budget (assertDeniedByRule fails on a budget denial in every mode).
// 2. Headroom: the hot rule keeps PAD spare expressions for its most expensive
//    ALLOWED request, so a small rule change cannot silently start denying.
//
// Background (measured 20 Nov 2026): in the rules engine `&&` evaluates every
// term even after one is false, so expensive helpers ran on requests a cheap
// check had already rejected. delegate_requests update now uses ternaries
// (`cheap ? next : false`), which evaluate one branch only.
const {test, describe, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertDeniedByRule, assertBudgetHeadroom,
} = require("./_rules_testing");

const RULES = readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8");
const UPDATE_LINE = "      allow update: if (signedIn()\n          && (!changedKeys().hasAny(['status']) || newDelegateApprovalPaymentOk())";
const ren = {
  requestType: "renewal", status: "pending",
  organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
  orgCompanyCheck: "ok",
  paymentStatus: "pending", paymentMethod: "paymob",
  fee: 500, periodCode: "2027_H1",
};

describe("delegate_requests update: denies come from a condition (TAS-106)", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();
  before(async () => {
    env = await initializeTestEnvironment({projectId: "demo-expression-budget", firestore: {rules: RULES}});
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sa").set({role: "super-admin"});
      await db.doc("users/tech").set({role: "technical_support", organizationUID: "o1"});
      await db.doc("users/hr1").set({role: "hr", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/oa1").set({role: "organization-admin", organizationUID: "o1"});
      await db.doc("delegate_requests/ren-unpaid").set(ren);
      await db.doc("delegate_requests/nd-unpaid").set({...ren, requestType: "new_delegate", periodCode: null});
    });
  });

  test("F14: nobody approves an unpaid Paymob renewal", async () => {
    for (const uid of ["sa", "tech", "hr1", "oa1"]) {
      await assertDeniedByRule(as(uid).doc("delegate_requests/ren-unpaid").update({status: "approved", reviewedBy: uid}));
    }
  });

  test("nobody approves an unpaid Paymob new_delegate", async () => {
    for (const uid of ["sa", "tech", "hr1", "oa1"]) {
      await assertDeniedByRule(as(uid).doc("delegate_requests/nd-unpaid").update({status: "approved", reviewedBy: uid}));
    }
  });

  test("clients cannot mark a request paid", async () => {
    await assertDeniedByRule(as("sa").doc("delegate_requests/ren-unpaid").update({paymentStatus: "paid"}));
    await assertDeniedByRule(as("hr1").doc("delegate_requests/ren-unpaid").update({paymentStatus: "paid"}));
  });

  test("clients cannot turn a request into update_national_id", async () => {
    await assertDeniedByRule(as("sa").doc("delegate_requests/ren-unpaid").update({requestType: "update_national_id"}));
  });

  test("still allowed: super-admin rejects the unpaid renewal", async () => {
    await assertSucceeds(as("sa").doc("delegate_requests/ren-unpaid").update({
      status: "rejected", reviewedBy: "SA", rejectionReason: "r",
    }));
  });
});

describe("expression budget headroom (TAS-105)", () => {
  // Spare expressions the hot path must keep. Raise it when the rule gets
  // cheaper; never lower it to make a rule change pass.
  const PAD = Number(process.env.RULES_BUDGET_PAD || 120); // measured ~162 spare on 20 Nov 2026

  test(`delegate_requests update keeps ${PAD} spare expressions (super-admin reject)`, async () => {
    await assertBudgetHeadroom({
      rules: RULES,
      line: UPDATE_LINE,
      pad: PAD,
      projectId: "demo-expression-budget-headroom",
      seed: async (db) => {
        await db.doc("users/sa").set({role: "super-admin"});
        await db.doc("delegate_requests/ren-unpaid").set(ren);
      },
      request: (e) => e.authenticatedContext("sa", {firebase: {sign_in_provider: "password"}}).firestore()
        .doc("delegate_requests/ren-unpaid").update({status: "rejected", reviewedBy: "SA", rejectionReason: "r"}),
    });
  });
});
