/**
 * delegate_requests subscription guard (PR feat/subscription-cycles).
 * Emulator only (demo-* project): npm run test:rules:subs
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");

describe("delegate_requests: payment is server-only", () => {
  let env;
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-tashil-subs-rules",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/sup2").set({role: "supervisor", organizationUID: "o2", companyUID: "c2"});
      await db.doc("users/hr1").set({role: "hr", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/hr2").set({role: "hr", organizationUID: "o2", companyUID: "c2"});
      await db.doc("users/admin1").set({role: "admin", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/oa1").set({role: "organization-admin", organizationUID: "o1"});
      await db.doc("users/oa2").set({role: "organization-admin", organizationUID: "o2"});
      await db.doc("users/sa").set({role: "super-admin"});
      await db.doc("users/tech").set({role: "technical_support"});
      await db.doc("users/d1").set({role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d1"});
      await db.doc("delegate_requests/pending").set({
        requestType: "renewal", status: "pending", paymentStatus: "pending",
        coveredDelegateUids: ["a"], amountDue: 416.67, periodCode: "2027_H1",
      });
      await db.doc("delegate_requests/paid").set({
        requestType: "renewal", status: "approved", paymentStatus: "paid",
        coveredDelegateUids: ["a"], amountDue: 416.67, periodCode: "2027_H1",
        paymob: {transactionId: "tx"},
      });
      await db.doc("delegate_requests/legacy").set({requestType: "new_delegate", status: "pending"});
      await db.doc("delegate_requests/scoped").set({
        requestType: "renewal", status: "pending", organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/other-co").set({
        requestType: "renewal", status: "pending", organizationUID: "o2", companyUID: "c2", supervisorUid: "sup2",
      });
      await db.doc("delegate_requests/self-d").set({
        requestType: "new_delegate", status: "pending", delegateUid: "d1", organizationUID: "o1", companyUID: "c1",
      });
    });
  });
  const as = (uid) => env.authenticatedContext(uid).firestore();

  test("HR creates a pending renewal (Mohamed policy: HR or company admin)", async () => {
    await assertSucceeds(as("hr1").doc("delegate_requests/new1").set({
      requestType: "renewal", status: "pending", paymentStatus: "pending", paymentMethod: "paymob",
      supervisorUid: "hr1",
      coveredDelegateUids: ["a", "b"], items: [{uid: "a", fee: 416.67}, {uid: "b", fee: 416.67}],
      amountDue: 833.34, periodCode: "2027_H1", companyUID: "c1",
    }));
  });

  test("nobody on a client can create or flip a request to paid", async () => {
    for (const uid of ["sup", "sa", "tech"]) {
      await assertFails(as(uid).doc(`delegate_requests/x-${uid}`).set({requestType: "renewal", paymentStatus: "paid"}));
      await assertFails(as(uid).doc("delegate_requests/pending").update({paymentStatus: "paid"}));
      await assertFails(as(uid).doc("delegate_requests/pending").update({paymob: {transactionId: "fake"}}));
    }
  });

  test("a paid request's coverage and amount are frozen", async () => {
    await assertFails(as("sup").doc("delegate_requests/paid").update({coveredDelegateUids: ["a", "b", "c"]}));
    await assertFails(as("sa").doc("delegate_requests/paid").update({amountDue: 1}));
    await assertFails(as("sa").doc("delegate_requests/paid").update({paymentStatus: "failed"}));
    await assertSucceeds(as("sa").doc("delegate_requests/paid").update({reviewedBy: "x"}));
  });

  test("unchanged flows still work: cancel unpaid, approve/reject legacy, edit pending", async () => {
    await assertSucceeds(as("sup").doc("delegate_requests/pending").update({status: "cancelled"}));
    await assertSucceeds(as("sa").doc("delegate_requests/legacy").update({status: "approved", reviewedBy: "SA"}));
    await assertSucceeds(as("tech").doc("delegate_requests/legacy").update({status: "rejected", rejectionReason: "r"}));
    await assertSucceeds(as("sa").doc("delegate_requests/legacy2").set({requestType: "delete_delegate", status: "pending"}));
  });

  test("delegate_requests reads: scoped staff, owners, global staff", async () => {
    await assertSucceeds(as("sup").doc("delegate_requests/scoped").get());
    await assertSucceeds(as("hr1").doc("delegate_requests/scoped").get());
    await assertFails(as("sup2").doc("delegate_requests/scoped").get());
    await assertFails(as("hr2").doc("delegate_requests/scoped").get());
    await assertSucceeds(as("oa1").doc("delegate_requests/scoped").get());
    await assertFails(as("oa2").doc("delegate_requests/scoped").get());
    await assertSucceeds(as("tech").doc("delegate_requests/other-co").get());
    await assertSucceeds(as("d1").doc("delegate_requests/self-d").get());
    await assertFails(as("d1").doc("delegate_requests/scoped").get());
  });

  test("clients cannot set applyState or payment error flags", async () => {
    await assertFails(as("hr1").doc("delegate_requests/pending").update({applyState: "applied"}));
    await assertFails(as("sa").doc("delegate_requests/pending").update({needsReview: true}));
    await assertFails(as("sup").doc("delegate_requests/pending").update({paymentError: "x"}));
  });

  test("delegate self cannot mark paid; staff legacy create without subscription fields still works", async () => {
    await assertFails(as("webuid").doc("delegate_requests/webuid").set({delegateUid: "webuid", status: "pending"}));
    await assertSucceeds(as("admin1").doc("delegate_requests/legacy3").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "admin1", companyUID: "c1",
    }));
  });
});
