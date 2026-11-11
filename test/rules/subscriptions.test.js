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
      await db.doc("users/oa1").set({role: "organization-admin", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/oa0").set({role: "organization-admin", organizationUID: "o1"});
      await db.doc("users/oa2").set({role: "organization-admin", organizationUID: "o2", companyUID: "c2"});
      await db.doc("users/sa").set({role: "super-admin"});
      await db.doc("users/tech").set({role: "technical_support"});
      await db.doc("users/d1").set({role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d1"});
      await db.doc("organizations/o1/companies/c1").set({companyUID: "c1"});
      await db.doc("organizations/o2/companies/c2").set({companyUID: "c2"});
      await db.doc("organizations/o3/companies/c1").set({companyUID: "c1"});
      await db.doc("delegate_requests/pending").set({
        requestType: "renewal", status: "pending", paymentStatus: "pending",
        coveredDelegateUids: ["a"], amountDue: 416.67, periodCode: "2027_H1",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/paid").set({
        requestType: "renewal", status: "approved", paymentStatus: "paid",
        coveredDelegateUids: ["a"], amountDue: 416.67, periodCode: "2027_H1",
        paymob: {transactionId: "tx"},
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/legacy").set({
        requestType: "new_delegate", status: "pending", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("delegate_requests/scoped").set({
        requestType: "renewal", status: "pending", organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/other-co").set({
        requestType: "renewal", status: "pending", organizationUID: "o2", companyUID: "c2", supervisorUid: "sup2",
      });
      await db.doc("delegate_requests/self-d").set({
        requestType: "new_delegate", status: "pending", orgCompanyCheck: "ok", delegateUid: "d1", organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("delegate_requests/nid-c1").set({
        requestType: "new_delegate", status: "pending", orgCompanyCheck: "ok", nationalId: "29101010100011",
        phoneNumber: "01011111111", receiptCode: "12345", existingDelegateUid: "d1",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/nid-c2").set({
        requestType: "new_delegate", status: "pending", orgCompanyCheck: "ok", nationalId: "29101010100011",
        phoneNumber: "01011111111", receiptCode: "12345", existingDelegateUid: "d1",
        organizationUID: "o2", companyUID: "c2", supervisorUid: "sup2",
      });
      await db.doc("delegate_requests/del-c1").set({
        requestType: "delete_delegate", status: "pending", existingDelegateUid: "d1",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/new-approved-c1").set({
        requestType: "new_delegate", status: "approved", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
      });
      // Same company, another organization/chain (o3 / c1).
      await db.doc("delegate_requests/nid-c1-other-chain").set({
        requestType: "new_delegate", status: "pending", orgCompanyCheck: "ok", nationalId: "29101010100011",
        phoneNumber: "01011111111", receiptCode: "12345", existingDelegateUid: "d3",
        organizationUID: "o3", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/renewal-c1-other-chain").set({
        requestType: "renewal", status: "pending",
        organizationUID: "o3", companyUID: "c1", supervisorUid: "sup",
      });
      await db.doc("delegate_requests/new-approved-c1-other-chain").set({
        requestType: "new_delegate", status: "approved", orgCompanyCheck: "ok",
        organizationUID: "o3", companyUID: "c1", supervisorUid: "sup",
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

  test("org-admin can create a renewal only in their own org and company", async () => {
    await assertSucceeds(as("oa1").doc("delegate_requests/oa-own").set({
      requestType: "renewal", status: "pending", paymentStatus: "pending", paymentMethod: "paymob",
      supervisorUid: "oa1",
      coveredDelegateUids: ["a"], items: [{uid: "a", fee: 416.67}],
      amountDue: 416.67, periodCode: "2027_H1", companyUID: "c1", organizationUID: "o1",
    }));
  });

  test("org-admin of o1 cannot create a renewal for a company in o2", async () => {
    await assertFails(as("oa1").doc("delegate_requests/oa-cross-org").set({
      requestType: "renewal", status: "pending", paymentStatus: "pending", paymentMethod: "paymob",
      supervisorUid: "oa1",
      coveredDelegateUids: ["a"], items: [{uid: "a", fee: 416.67}],
      amountDue: 416.67, periodCode: "2027_H1", companyUID: "c2", organizationUID: "o2",
    }));
  });

  test("org-admin with no companyUID cannot create a renewal", async () => {
    await assertFails(as("oa0").doc("delegate_requests/oa-no-company").set({
      requestType: "renewal", status: "pending", paymentStatus: "pending", paymentMethod: "paymob",
      supervisorUid: "oa0",
      coveredDelegateUids: ["a"], items: [{uid: "a", fee: 416.67}],
      amountDue: 416.67, periodCode: "2027_H1", companyUID: "c1", organizationUID: "o1",
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
    // Company staff can get a request in another chain of the same company.
    await assertSucceeds(as("sup").doc("delegate_requests/nid-c1-other-chain").get());
    await assertSucceeds(as("hr1").doc("delegate_requests/nid-c1-other-chain").get());
    await assertSucceeds(as("admin1").doc("delegate_requests/nid-c1-other-chain").get());
    await assertFails(as("oa1").doc("delegate_requests/nid-c1-other-chain").get());
    await assertFails(as("sup2").doc("delegate_requests/nid-c1-other-chain").get());
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

  test("company staff list shapes use companyUID only and include other chains", async () => {
    const col = (uid) => as(uid).collection("delegate_requests");
    const byCo = (q, co) => q.where("companyUID", "==", co);

    // Each staff list shape (nationalId, phone, pending delete, receipt code,
    // pending queue, approved new-delegate, pending renewal) — company only.
    await assertSucceeds(byCo(col("sup").where("nationalId", "==", "29101010100011"), "c1").get());
    await assertSucceeds(byCo(col("hr1").where("phoneNumber", "==", "01011111111"), "c1").get());
    await assertSucceeds(byCo(
      col("admin1").where("existingDelegateUid", "==", "d1").where("requestType", "==", "delete_delegate").where("status", "==", "pending"),
      "c1",
    ).get());
    await assertSucceeds(byCo(col("sup").where("receiptCode", "==", "12345"), "c1").get());
    await assertSucceeds(byCo(col("hr1").where("status", "==", "pending"), "c1").get());
    await assertSucceeds(byCo(
      col("admin1").where("requestType", "==", "new_delegate").where("status", "==", "approved"),
      "c1",
    ).get());
    await assertSucceeds(byCo(
      col("sup").where("requestType", "==", "renewal").where("status", "==", "pending"),
      "c1",
    ).get());

    // Same-company, other-chain docs are visible via companyUID-only lists.
    const nid = await byCo(col("sup").where("nationalId", "==", "29101010100011"), "c1").get();
    const nidIds = nid.docs.map((d) => d.id);
    if (!nidIds.includes("nid-c1") || !nidIds.includes("nid-c1-other-chain")) {
      throw new Error("expected both chains of c1 in the nationalId list, got " + nidIds.join(","));
    }
    const pending = await byCo(col("hr1").where("status", "==", "pending"), "c1").get();
    const pendingIds = pending.docs.map((d) => d.id);
    if (!pendingIds.includes("nid-c1-other-chain") || !pendingIds.includes("renewal-c1-other-chain")) {
      throw new Error("expected other-chain pending docs, got " + pendingIds.join(","));
    }
    await assertSucceeds(byCo(
      col("admin1").where("requestType", "==", "new_delegate").where("status", "==", "approved"),
      "c1",
    ).get());

    // Unscoped lists (no companyUID) stay denied for company staff.
    await assertFails(col("sup").where("nationalId", "==", "29101010100011").get());
    await assertFails(col("sup").where("phoneNumber", "==", "01011111111").get());
    await assertFails(col("sup").where("receiptCode", "==", "12345").get());
    await assertFails(col("sup").where("organizationUID", "==", "o1").where("status", "==", "pending").get());
    await assertFails(col("sup").where("existingDelegateUid", "==", "d1").where("requestType", "==", "delete_delegate").where("status", "==", "pending").get());
  });

  test("cross-company staff list reads stay denied; org-admin and global paths still work", async () => {
    const col = (uid) => as(uid).collection("delegate_requests");
    // Company staff of c1 cannot list c2, even with the other company's filters.
    await assertFails(col("sup").where("companyUID", "==", "c2").where("nationalId", "==", "29101010100011").get());
    await assertFails(col("hr1").where("companyUID", "==", "c2").where("status", "==", "pending").get());
    await assertFails(col("admin1").where("companyUID", "==", "c2").where("receiptCode", "==", "12345").get());
    await assertFails(
      col("sup").where("organizationUID", "==", "o2").where("companyUID", "==", "c2").where("requestType", "==", "renewal").where("status", "==", "pending").get(),
    );
    // Org-admin of o1 cannot list o2 or the other chain (o3) of company c1.
    await assertFails(col("oa1").where("organizationUID", "==", "o2").get());
    await assertFails(col("oa1").where("organizationUID", "==", "o3").get());
    await assertSucceeds(col("oa1").where("organizationUID", "==", "o1").get());
    await assertSucceeds(col("oa1").where("organizationUID", "==", "o1").where("status", "==", "pending").get());
    // Global staff may list without company filters.
    await assertSucceeds(col("tech").where("status", "==", "pending").get());
    await assertSucceeds(col("sa").where("nationalId", "==", "29101010100011").get());
  });


  test("company staff can create in their company and cannot create in another company", async () => {
    await assertSucceeds(as("admin1").doc("delegate_requests/create-same-co").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "admin1",
      companyUID: "c1", organizationUID: "o3",
    }));
    await assertSucceeds(as("hr1").doc("delegate_requests/create-same-co-hr").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "hr1",
      companyUID: "c1", organizationUID: "o1",
    }));
    await assertFails(as("admin1").doc("delegate_requests/create-other-co").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "admin1",
      companyUID: "c2", organizationUID: "o2",
    }));
    await assertFails(as("hr1").doc("delegate_requests/create-other-co-hr").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "hr1",
      companyUID: "c2",
    }));
    await assertFails(as("sup").doc("delegate_requests/create-missing-co").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "sup",
      organizationUID: "o1",
    }));
  });

  test("requestStaffUpdateOk is company-scoped and blocks approval fields", async () => {
    // Same-company staff may still cancel an unpaid renewal (app cancelRenewal).
    await assertSucceeds(as("sup").doc("delegate_requests/pending").update({status: "cancelled"}));
    // Name / phone / images go through editDelegateProfile only (M-1).
    await assertFails(as("hr1").doc("delegate_requests/nid-c1-other-chain").update({firstName: "N"}));
    // Non-profile metadata remains editable in their company, including
    // another chain of the same company.
    await assertSucceeds(as("hr1").doc("delegate_requests/nid-c1-other-chain").update({updatedAt: "t"}));
    // Cross-company updates are denied.
    await assertFails(as("sup2").doc("delegate_requests/scoped").update({firstName: "x"}));
    await assertFails(as("oa2").doc("delegate_requests/scoped").update({firstName: "x"}));
    // Company / org staff cannot approve, reject, or change national ID,
    // org/company ids, payment, or approval fields.
    await assertFails(as("sup").doc("delegate_requests/scoped").update({status: "approved", reviewedBy: "s"}));
    await assertFails(as("admin1").doc("delegate_requests/scoped").update({status: "rejected", rejectionReason: "r"}));
    await assertFails(as("hr1").doc("delegate_requests/scoped").update({nationalId: "000"}));
    await assertFails(as("oa1").doc("delegate_requests/scoped").update({companyUID: "c9"}));
    await assertFails(as("oa1").doc("delegate_requests/scoped").update({status: "approved"}));
    // Org-admin cannot change profile fields either; they may still cancel.
    await assertFails(as("oa1").doc("delegate_requests/scoped").update({firstName: "OrgEdit"}));
    await assertSucceeds(as("oa1").doc("delegate_requests/scoped").update({updatedAt: "t"}));
    await assertSucceeds(as("oa1").doc("delegate_requests/del-c1").update({status: "cancelled"}));
    // Only super-admin / technical support may approve or reject.
    await assertSucceeds(as("sa").doc("delegate_requests/legacy").update({status: "approved", reviewedBy: "SA"}));
    await assertSucceeds(as("tech").doc("delegate_requests/nid-c1").update({status: "rejected", rejectionReason: "r"}));
  });

  test("company staff cannot cancel a paid renewal or write quotedAt", async () => {
    await assertFails(as("sup").doc("delegate_requests/paid").update({status: "cancelled"}));
    await assertFails(as("hr1").doc("delegate_requests/paid").update({status: "cancelled"}));
    await assertFails(as("oa1").doc("delegate_requests/paid").update({status: "cancelled"}));
    await assertFails(as("sa").doc("delegate_requests/paid").update({status: "cancelled"}));
    await assertFails(as("sup").doc("delegate_requests/pending").update({quotedAt: "2027-04-01T00:00:00Z"}));
    await assertFails(as("sa").doc("delegate_requests/pending").update({quotedAt: "2027-04-01T00:00:00Z"}));
  });

  test("organizationUIDs is capped after create and the primary chain must belong to the company", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("delegate_requests/multi").set({
        requestType: "new_delegate", status: "pending",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
        organizationUIDs: ["o1", "o3"],
      });
    });
    const twelve = Array.from({length: 12}, (_, i) => i === 0 ? "o1" : `ox${i}`);
    await assertFails(as("sup").doc("delegate_requests/multi").update({organizationUIDs: twelve}));
    await assertFails(as("sa").doc("delegate_requests/multi").update({organizationUIDs: twelve}));
    await assertSucceeds(as("sa").doc("delegate_requests/multi").update({organizationUIDs: ["o1"]}));
    await assertFails(as("sa").doc("delegate_requests/no-such-chain").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "sa",
      organizationUID: "missing-org", companyUID: "c1",
      organizationUIDs: ["missing-org"],
    }));
  });


  test("staff can get a paid receipt and list paid renewals; other companies cannot", async () => {
    // Get-by-id after payment (receipt page).
    await assertSucceeds(as("hr1").doc("delegate_requests/paid").get());
    await assertSucceeds(as("sup").doc("delegate_requests/paid").get());
    await assertSucceeds(as("admin1").doc("delegate_requests/paid").get());
    await assertSucceeds(as("oa1").doc("delegate_requests/paid").get());
    await assertFails(as("sup2").doc("delegate_requests/paid").get());
    await assertFails(as("hr2").doc("delegate_requests/paid").get());
    await assertFails(as("d1").doc("delegate_requests/paid").get());

    const col = (uid) => as(uid).collection("delegate_requests");
    // App query: companyUID + requestType=renewal + paymentStatus=paid.
    const companyPaid = (uid, co) => col(uid)
      .where("companyUID", "==", co)
      .where("requestType", "==", "renewal")
      .where("paymentStatus", "==", "paid");
    await assertSucceeds(companyPaid("hr1", "c1").get());
    await assertSucceeds(companyPaid("sup", "c1").get());
    await assertSucceeds(companyPaid("admin1", "c1").get());
    // Org-admin also scopes by organizationUID.
    await assertSucceeds(
      companyPaid("oa1", "c1").where("organizationUID", "==", "o1").get(),
    );
    await assertSucceeds(col("oa1")
      .where("organizationUID", "==", "o1")
      .where("requestType", "==", "renewal")
      .where("paymentStatus", "==", "paid")
      .get());
    const paid = await companyPaid("hr1", "c1").get();
    const ids = paid.docs.map((d) => d.id);
    if (!ids.includes("paid")) {
      throw new Error("expected paid receipt in the company list, got " + ids.join(","));
    }
    // Cross-company and unscoped lists stay denied.
    await assertFails(companyPaid("hr1", "c2").get());
    await assertFails(companyPaid("sup2", "c1").get());
    await assertFails(col("hr1").where("requestType", "==", "renewal").where("paymentStatus", "==", "paid").get());
  });

  test("clients cannot flip orgCompanyCheck and cannot approve without ok", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("delegate_requests/mark-failed").set({
        requestType: "new_delegate", status: "pending",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
        orgCompanyCheck: "failed", orgCompanyCheckReason: "org_not_in_company",
        organizationUIDs: ["o1", "oX"],
      });
      await db.doc("delegate_requests/mark-ok").set({
        requestType: "new_delegate", status: "pending",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
        orgCompanyCheck: "ok",
        paymentStatus: "waived",
      });
      await db.doc("delegate_requests/paymob-unpaid").set({
        requestType: "new_delegate", status: "pending",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
        orgCompanyCheck: "ok",
        paymentStatus: "pending", paymentMethod: "paymob",
        fee: 500,
      });
    });
    await assertFails(as("hr1").doc("delegate_requests/mark-failed").update({orgCompanyCheck: "ok"}));
    await assertFails(as("oa1").doc("delegate_requests/mark-failed").update({orgCompanyCheck: "ok"}));
    await assertFails(as("sa").doc("delegate_requests/mark-failed").update({orgCompanyCheck: "ok"}));
    await assertFails(as("sa").doc("delegate_requests/mark-failed").update({status: "approved", reviewedBy: "SA"}));
    await assertFails(as("hr1").doc("delegate_requests/new-with-mark").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "hr1",
      companyUID: "c1", organizationUID: "o1", orgCompanyCheck: "ok",
    }));
    await assertSucceeds(as("sa").doc("delegate_requests/mark-ok").update({status: "approved", reviewedBy: "SA"}));
    await assertFails(as("sa").doc("delegate_requests/paymob-unpaid").update({status: "approved", reviewedBy: "SA"}));
  });

  test("clients can create waived requests before the promo end instant", async () => {
    await assertSucceeds(as("hr1").doc("delegate_requests/waived-before").set({
      requestType: "new_delegate", status: "pending", supervisorUid: "hr1",
      companyUID: "c1", organizationUID: "o1",
      paymentStatus: "waived", paymentMethod: "free_promotion", fee: 0,
    }));
  });

});
