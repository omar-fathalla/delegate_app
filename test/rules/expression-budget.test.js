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
  // Spare pad units (trueTree leaves) the hot path must keep. Raise it when the rule gets
  // cheaper; never lower it to make a rule change pass.
  const PAD = Number(process.env.RULES_BUDGET_PAD || 120); // measured ~162 spare pad units on 20 Nov 2026

  test(`delegate_requests update keeps ${PAD} spare pad units (super-admin reject)`, async () => {
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

  // Measured 20 Nov 2026 by padding each rule and re-running every rules suite
  // until an existing ALLOW test broke. Spare pad units (lower..upper bound):
  //   delegates update 40..45, attendance_logs create 25..30, tasks update 20..25.
  // These are thin: ~20-45 units before a real, allowed write is denied.
  // Each guard keeps a margin of 5 below the measured lower bound. TAS-108
  // (delegates) should raise its PAD once the rule is cheaper.
  const DELEGATE_PAD = Number(process.env.RULES_BUDGET_PAD_DELEGATES || 35);
  const ATTENDANCE_PAD = Number(process.env.RULES_BUDGET_PAD_ATTENDANCE || 20);
  const TASKS_PAD = Number(process.env.RULES_BUDGET_PAD_TASKS || 15);

  // Worst ALLOW in docs-pending.test.js: delegate self-update with 8 approved
  // entries, photo re-upload backing entry moved to slot 7, on the top-level
  // path (the nested path measured cheaper).
  const KEYS = ["personalPhoto", "nationalityId", "authorizationLetter", "insuranceLetter",
    "healthCertificate", "paymentReceipt", "electronicPaymentReceipt", "electronic_payment_receipt"];
  const EIGHT = KEYS.map((k) => ({documentKey: k, documentStatus: "approved", documentURL: k + "0",
    secondaryURL: "s", uploadedAt: "2026-01-01", reviewedBy: "x"}));
  const TOP_D1 = "delegates/d1";

  test(`delegates update keeps ${DELEGATE_PAD} spare pad units (delegate 8-entry photo re-upload)`, async () => {
    await assertBudgetHeadroom({
      rules: RULES,
      line: "allow update: if signedIn() && !onNestedDelegate()",
      pad: DELEGATE_PAD,
      projectId: "demo-expression-budget-delegates",
      seed: async (db) => {
        await db.doc("users/d1").set({role: "delegate", organizationUID: "o1", companyUID: "c1"});
        await db.doc("organizations/o1").set({name: "O1"});
        await db.doc("organizations/o1/companies/c1").set({name: "C1"});
        await db.doc(TOP_D1).set({
          uid: "d1", organizationUID: "o1", companyUID: "c1", status: "active", fullName: "Fake",
          profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", documents: EIGHT,
        });
      },
      request: (e) => e.authenticatedContext("d1", {firebase: {sign_in_provider: "password"}, role: "delegate"})
        .firestore().doc(TOP_D1).update({
          documents: [...EIGHT.slice(1).reverse(), {...EIGHT[0], documentStatus: "pending", documentURL: "p9"}],
          profileImageUrl: "p9", personalPhotoURL: "p9", updatedAt: "t",
        }),
    });
  });

  // Worst ALLOW in firestore.rules.test.js: OTP-verified delegate check-in
  // under OTP enforcement.
  const DELEGATE_TOKEN = {
    role: "delegate", delegateId: "del-1", delegateIds: ["del-1", "del-2"], orgId: "o1", companyId: "c1",
    phones: ["01011111111", "+201011111111"], firebase: {sign_in_provider: "custom"},
  };
  const seedDel1 = async (db) => {
    await db.doc("organizations/o1").set({name: "Org 1", admins: 1});
    await db.doc("organizations/o1/companies/c1").set({name: "Company 1"});
    await db.doc("organizations/o1/companies/c1/delegates/del-1").set({
      phoneNumber: "01011111111", organizationUID: "o1", companyUID: "c1",
      role: "delegate", status: "active", uid: "del-1",
    });
  };

  test(`attendance_logs create keeps ${ATTENDANCE_PAD} spare pad units (OTP-verified delegate check-in)`, async () => {
    await assertBudgetHeadroom({
      rules: RULES,
      line: "allow read: if staffToken() && canReadOrgAdminAttendanceByOrgId();\n      allow read: if canReadAttendance();\n" +
        "      allow create: if canCreateAttendance();",
      pad: ATTENDANCE_PAD,
      projectId: "demo-expression-budget-attendance",
      seed: seedDel1,
      request: (e) => e.authenticatedContext("del-1", {...DELEGATE_TOKEN, otp_required: true, otp_verified: true})
        .firestore().collection("attendance_logs").add({
          delegateId: "del-1", userId: "del-1", organizationId: "o1", companyId: "c1",
        }),
    });
  });

  // Worst ALLOW in firestore.rules.test.js: assigned delegate completes a task.
  test(`tasks update keeps ${TASKS_PAD} spare pad units (delegate completes a task)`, async () => {
    await assertBudgetHeadroom({
      rules: RULES,
      line: "allow update: if signedIn() && taskCanUpdate();",
      pad: TASKS_PAD,
      projectId: "demo-expression-budget-tasks",
      seed: async (db) => {
        await seedDel1(db);
        await db.doc("users/comp").set({role: "company-admin", organizationUID: "o1", companyUID: "c1"});
        await db.doc("organizations/o1/tasks/sent").set({
          companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "Sent", description: "Body",
          status: "pending", imageUrl: "https://example.com/a.jpg", imagePath: "organizations/o1/task_images/comp/a.jpg",
        });
      },
      request: (e) => e.authenticatedContext("del-1", DELEGATE_TOKEN).firestore()
        .doc("organizations/o1/tasks/sent").update({status: "completed", completedBy: "del-1", notes: "done"}),
    });
  });
});
