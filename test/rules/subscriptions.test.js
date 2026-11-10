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
      await db.doc("delegate_requests/nid-c1").set({
        requestType: "new_delegate", status: "pending", nationalId: "29101010100011",
        phoneNumber: "01011111111", receiptCode: "12345", existingDelegateUid: "d1",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/nid-c2").set({
        requestType: "new_delegate", status: "pending", nationalId: "29101010100011",
        phoneNumber: "01011111111", receiptCode: "12345", existingDelegateUid: "d1",
        organizationUID: "o2", companyUID: "c2", supervisorUid: "sup2",
      });
      await db.doc("delegate_requests/del-c1").set({
        requestType: "delete_delegate", status: "pending", existingDelegateUid: "d1",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/new-approved-c1").set({
        requestType: "new_delegate", status: "approved",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
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

  test("staff list query shapes require organizationUID and companyUID", async () => {
    const col = (uid) => as(uid).collection("delegate_requests");
    const orgCo = (q, org, co) => q.where("organizationUID", "==", org).where("companyUID", "==", co);

    // Each staff list shape used by the app (nationalId, phone, pending delete,
    // receipt code, pending queue, approved new-delegate, pending renewal).
    await assertSucceeds(orgCo(col("sup").where("nationalId", "==", "29101010100011"), "o1", "c1").get());
    await assertSucceeds(orgCo(col("hr1").where("phoneNumber", "==", "01011111111"), "o1", "c1").get());
    await assertSucceeds(orgCo(
      col("admin1").where("existingDelegateUid", "==", "d1").where("requestType", "==", "delete_delegate").where("status", "==", "pending"),
      "o1", "c1",
    ).get());
    await assertSucceeds(orgCo(col("sup").where("receiptCode", "==", "12345"), "o1", "c1").get());
    await assertSucceeds(orgCo(col("hr1").where("status", "==", "pending"), "o1", "c1").get());
    await assertSucceeds(orgCo(
      col("admin1").where("requestType", "==", "new_delegate").where("status", "==", "approved"),
      "o1", "c1",
    ).get());
    await assertSucceeds(orgCo(
      col("sup").where("requestType", "==", "renewal").where("status", "==", "pending"),
      "o1", "c1",
    ).get());

    // Missing org or company (the broken client shapes) is denied for company staff.
    await assertFails(col("sup").where("nationalId", "==", "29101010100011").get());
    await assertFails(col("sup").where("phoneNumber", "==", "01011111111").get());
    await assertFails(col("sup").where("receiptCode", "==", "12345").get());
    await assertFails(col("sup").where("companyUID", "==", "c1").where("status", "==", "pending").get());
    await assertFails(col("sup").where("organizationUID", "==", "o1").where("status", "==", "pending").get());
    await assertFails(col("sup").where("existingDelegateUid", "==", "d1").where("requestType", "==", "delete_delegate").where("status", "==", "pending").get());
    await assertFails(col("sup").where("companyUID", "==", "c1").where("requestType", "==", "new_delegate").where("status", "==", "approved").get());
    await assertFails(col("sup").where("companyUID", "==", "c1").where("requestType", "==", "renewal").where("status", "==", "pending").get());
  });

  test("cross-company staff list reads stay denied even with org+company filters", async () => {
    const col = (uid) => as(uid).collection("delegate_requests");
    // Supervisor / HR of c1 cannot list c2 by supplying the other company's filters.
    await assertFails(
      col("sup").where("organizationUID", "==", "o2").where("companyUID", "==", "c2").where("nationalId", "==", "29101010100011").get(),
    );
    await assertFails(
      col("hr1").where("organizationUID", "==", "o2").where("companyUID", "==", "c2").where("status", "==", "pending").get(),
    );
    await assertFails(
      col("admin1").where("organizationUID", "==", "o2").where("companyUID", "==", "c2").where("receiptCode", "==", "12345").get(),
    );
    // Org-admin of o1 cannot list o2.
    await assertFails(col("oa1").where("organizationUID", "==", "o2").get());
    await assertSucceeds(col("oa1").where("organizationUID", "==", "o1").get());
    // Global staff may list without company filters.
    await assertSucceeds(col("tech").where("status", "==", "pending").get());
  });

});
