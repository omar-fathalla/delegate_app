/**
 * Subscription suspension + Paymob payment hook against the Firestore emulator.
 * Default holds mode is shadow: M1/M2 write holds, not status.
 *   npm run test:e2e:subscriptions
 * Emulator only (demo-* project). Nothing here talks to a real project.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../../functions/node_modules/firebase-admin");
const J = require("../../functions/lib/subscription_jobs");
const L = require("../../functions/lib/subscription_logic");

if (admin.apps.length === 0) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tashil-subs"});
const db = admin.firestore();

const JAN1_2027 = L.cairoMidnight(2027, 1, 1); // first paid period starts
const JAN15_2027 = L.cairoMidnight(2027, 1, 15); // grace ends → suspension day
const JUL15_2027 = L.cairoMidnight(2027, 7, 15);
const FEB_2027 = new Date(Date.UTC(2027, 1, 10, 10));
const delegatePath = (org, uid) => `organizations/${org}/companies/c1/delegates/${uid}`;

async function seed() {
  const req = (id, extra = {}) => db.doc(`delegate_requests/${id}`).set({
    requestType: "new_delegate", status: "approved", supervisorUid: "sup1", companyUID: "c1",
    periodCode: "2026_H2", paymentStatus: "waived", ...extra,
  });
  // Three app-added delegates (one in two chains), one web-added, one manually suspended, one pending.
  for (const id of ["app1", "app2", "app3", "manual", "pend"]) await req(id);
  await db.doc("delegate_requests/pend").update({status: "pending"});
  await db.doc("delegate_requests/web1").set({delegateUid: "web1", status: "approved"}); // web self-request
  const del = (org, uid, status, extra = {}) => db.doc(delegatePath(org, uid)).set({uid, status, companyUID: "c1", ...extra});
  await del("o1", "app1", "active", {registeredVia: "mobile_app"});
  await del("o2", "app1", "active", {registeredVia: "mobile_app"}); // second chain, same subscription
  await del("o1", "app2", "active");
  await del("o1", "app3", "approved");
  await del("o1", "manual", "suspended", {statusReason: "manual"});
  await del("o1", "pend", "pending");
  await del("o1", "web1", "active", {registeredVia: "web"});
  await del("o2", "web2", "active", {registeredVia: "mobile_app"}); // mislabeled by an old add-org, no app request
  await db.doc("users/app1").set({role: "delegate", status: "active"});
  await db.doc("users/web1").set({role: "delegate", status: "active"});
  await db.doc("users/sup1").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
  // A company in another org: c2 for wrong-company checks.
  await db.doc("delegate_requests/other").set({
    requestType: "new_delegate", status: "approved", supervisorUid: "sup2", companyUID: "c2",
  });
  await db.doc("organizations/o1/companies/c2/delegates/other").set({uid: "other", status: "active", companyUID: "c2"});
}

const status = async (org, uid) => (await db.doc(delegatePath(org, uid)).get()).get("status");
const expiryHold = async (org, uid) => {
  const holds = (await db.doc(delegatePath(org, uid)).get()).get("holds") || {};
  return holds.subscription_expired || null;
};

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "run under the Firestore emulator");
  await seed();
});
test.after(async () => { await Promise.all(admin.apps.map((a) => a && a.delete())); });

test("no suspension during the free promotion (2026)", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN1_2027.getTime() - 1000));
  assert.equal(res.skipped, "free_promotion");
  assert.equal(await status("o1", "app1"), "active");
});

test("grace: no new suspension during 1–14 Jan after period end", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN1_2027.getTime() + 5 * 60 * 1000));
  assert.equal(res.skipped, "grace_period");
  assert.equal(res.suspendedDocs, 0);
  assert.equal(await status("o1", "app1"), "active");
  assert.equal(await expiryHold("o1", "app1"), null);
});

test("period end: app-added delegates get an expiry hold in every chain; web and pending untouched", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN15_2027.getTime() + 5 * 60 * 1000));
  assert.equal(res.periodCode, "2027_H1");
  // app1 x2, app2, app3, other (c2), plus stacking on the manual suspension.
  assert.equal(res.suspendedDocs, 6);
  assert.equal(res.suspendedUsers, 0); // users/{uid} is mirrored later, in authoritative mode
  for (const [o, u, st] of [["o1", "app1", "active"], ["o2", "app1", "active"], ["o1", "app2", "active"], ["o1", "app3", "approved"]]) {
    // Shadow: status is unchanged; the hold is the new signal.
    assert.equal(await status(o, u), st, `${o}/${u}`);
    const d = (await db.doc(delegatePath(o, u)).get()).data();
    assert.equal(d.statusReason, undefined);
    assert.equal(d.subscription.suspendedForPeriod, "2027_H1");
    assert.equal(d.holds.subscription_expired.periodCode, "2027_H1");
  }
  assert.equal(await status("o1", "web1"), "active");
  assert.equal(await expiryHold("o1", "web1"), null);
  assert.equal(await status("o2", "web2"), "active");
  assert.equal(await expiryHold("o2", "web2"), null);
  const manual = (await db.doc(delegatePath("o1", "manual")).get()).data();
  assert.equal(manual.status, "suspended");
  assert.equal(manual.statusReason, "manual"); // not overwritten in shadow
  assert.ok(manual.holds.subscription_expired);
  assert.equal(await status("o1", "pend"), "pending");
  assert.equal(await expiryHold("o1", "pend"), null);
  assert.equal((await db.doc("users/app1").get()).get("status"), "active");
  assert.equal((await db.doc("users/web1").get()).get("status"), "active");
  const runs = await db.collection("subscription_suspension_runs")
    .where("periodCode", "==", "2027_H1")
    .where("suspendedDocs", "==", 6)
    .get();
  assert.equal(runs.size, 1);
});

test("idempotent: a second run changes nothing", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN15_2027.getTime() + 60 * 60 * 1000));
  assert.equal(res.suspendedDocs, 0);
  assert.equal(res.suspendedUsers, 0);
  assert.equal(res.alreadySuspended, 6); // 5 app-added chains + the stacked manual
});

async function renewal(id, uids, extra = {}) {
  const fee = L.feeAt(FEB_2027);
  await db.doc(`delegate_requests/${id}`).set({
    requestType: "renewal", status: "pending", supervisorUid: "sup1", companyUID: "c1",
    organizationUID: "o1",
    periodCode: "2027_H1", paymentStatus: "pending", coveredDelegateUids: uids,
    items: uids.map((uid) => ({uid, fee})), amountDue: L.roundMoney(fee * uids.length), ...extra,
  });
}
const pay = (requestId, tx, amountCents, success = true) => J.applyVerifiedSubscriptionPayment(db, {
  requestId, paymobTransactionId: tx, paymobOrderId: `o-${tx}`, success, amountCents, currency: "EGP", paidAt: FEB_2027,
});

async function lateAppAdded(uid) {
  // Registration request only: enough for assertRenewable. A live delegate
  // doc would be an extra uncovered app-added uid and would change later
  // suspension counts in this shared-state suite.
  await db.doc(`delegate_requests/${uid}`).set({
    requestType: "new_delegate", status: "approved", supervisorUid: "sup1", companyUID: "c1",
    periodCode: "2026_H2", paymentStatus: "waived",
  });
}


test("quote: partial selection, server-computed total, refuses web or other-company delegates", async () => {
  await renewal("ren1", ["app1", "app2"]);
  const q = await J.quoteSubscriptionRequest(db, "ren1", FEB_2027);
  assert.equal(q.amount, 833.34);
  assert.equal(q.amountCents, 83334);
  await renewal("renWeb", ["app1", "web1"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renWeb", FEB_2027), /not_app_added/);
  await renewal("renOther", ["other"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renOther", FEB_2027), /wrong_company/);
  await assert.rejects(J.quoteSubscriptionRequest(db, "ren1", new Date(Date.UTC(2027, 7, 1, 10))), /period_mismatch/);
});

test("quote is recomputed when the month changes in the same period", async () => {
  await lateAppAdded("app4");
  const jan = L.cairoMidnight(2027, 1, 15);
  await renewal("renStale", ["app4"], {
    amountDue: L.feeAt(jan),
    fee: L.feeAt(jan),
    remainingMonths: 6,
    items: [{uid: "app4", fullName: "App Four", fee: L.feeAt(jan)}],
  });
  const q = await J.quoteSubscriptionRequest(db, "renStale", FEB_2027);
  assert.equal(q.amount, 416.67);
  assert.equal(q.remainingMonths, 5);
  const stored = (await db.doc("delegate_requests/renStale").get()).data();
  assert.equal(stored.amountDue, 416.67);
  assert.equal(stored.fee, 416.67);
  assert.equal(stored.remainingMonths, 5);
  assert.equal(stored.items[0].fee, 416.67);
  assert.equal(stored.items[0].fullName, "App Four");
  await db.doc("delegate_requests/renStale").update({status: "cancelled"});
});

test("failed payment: nobody is reactivated; retry allowed", async () => {
  assert.equal(await pay("ren1", "tx-fail", 83334, false), "failed");
  const r = (await db.doc("delegate_requests/ren1").get()).data();
  assert.equal(r.paymentStatus, "failed");
  assert.ok(await expiryHold("o1", "app1"));
  assert.ok(await expiryHold("o1", "app2"));
});

test("wrong amount is rejected for review and activates nobody", async () => {
  assert.equal(await pay("ren1", "tx-short", 100), "rejected");
  const r = (await db.doc("delegate_requests/ren1").get()).data();
  assert.equal(r.paymentError, "amount_mismatch");
  assert.equal(r.needsReview, true);
  assert.ok(await expiryHold("o1", "app1"));
});

test("verified payment reactivates only the selected delegates, in all their chains", async () => {
  assert.equal(await pay("ren1", "tx-ok", 83334), "paid");
  const r = (await db.doc("delegate_requests/ren1").get()).data();
  assert.equal(r.paymentStatus, "paid");
  assert.equal(r.status, "approved");
  assert.equal(r.applyState, "applied");
  assert.equal(r.paymob.transactionId, "tx-ok");
  for (const [o, u] of [["o1", "app1"], ["o2", "app1"], ["o1", "app2"]]) {
    const d = (await db.doc(delegatePath(o, u)).get()).data();
    assert.equal(d.status, "active", `${o}/${u}`);
    assert.equal(d.statusReason, undefined);
    assert.equal(d.holds && d.holds.subscription_expired, undefined, `${o}/${u} hold`);
    assert.equal(d.subscription.periodCode, "2027_H1");
    assert.equal(d.subscription.periodStart, "2027-01-01");
    assert.equal(d.subscription.periodEnd, "2027-06-30");
    assert.equal(d.subscription.amountDue, 416.67);
    assert.equal(d.subscription.paymentStatus, "paid");
    assert.equal(d.subscription.renewalRequestId, "ren1");
  }
  assert.ok(await expiryHold("o1", "app3")); // not selected: renew later
  assert.equal((await db.doc("users/app1").get()).get("status"), "active");
});

test("webhook replay and double payment are no-ops", async () => {
  assert.equal(await pay("ren1", "tx-ok", 83334), "duplicate");
  assert.equal(await pay("ren1", "tx-ok-2", 83334), "already_paid");
});

test("paid renewal keeps them active on the next daily run; the unselected one stays suspended", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(Date.UTC(2027, 1, 11, 10)));
  assert.equal(res.covered, 2);
  assert.equal(res.suspendedDocs, 0);
  assert.equal(await expiryHold("o1", "app1"), null);
  assert.ok(await expiryHold("o1", "app3"));
});

test("clearing the expiry hold without payment is undone by the next run", async () => {
  await db.doc(delegatePath("o1", "app3")).update({status: "active", holds: {}});
  const res = await J.runSubscriptionSuspension(db, new Date(Date.UTC(2027, 1, 12, 10)));
  assert.equal(res.suspendedDocs, 1);
  assert.ok(await expiryHold("o1", "app3"));
  // Shadow: status is not rewritten.
  assert.equal(await status("o1", "app3"), "active");
});

test("renewing the rest later: second partial renewal", async () => {
  await renewal("ren2", ["app3"]);
  const q = await J.quoteSubscriptionRequest(db, "ren2", FEB_2027);
  assert.equal(q.amountCents, 41667);
  assert.equal(await pay("ren2", "tx-2", 41667), "paid");
  assert.equal(await expiryHold("o1", "app3"), null);
  assert.equal(await status("o1", "app3"), "active");
});

test("quote refuses a renewal whose creator is out of org or has no company", async () => {
  await db.doc("users/oa-other").set({role: "organization-admin", organizationUID: "o2", companyUID: "c2"});
  await db.doc("users/oa-none").set({role: "organization-admin", organizationUID: "o1"});
  await renewal("renWrongOrg", ["app4"], {supervisorUid: "oa-other"});
  await assert.rejects(J.quoteSubscriptionRequest(db, "renWrongOrg", FEB_2027), /creator_wrong_org/);
  await renewal("renNoCo", ["app4"], {supervisorUid: "oa-none"});
  await assert.rejects(J.quoteSubscriptionRequest(db, "renNoCo", FEB_2027), /creator_wrong_company/);
});

test("a uid already on a pending or paid renewal cannot be quoted or charged twice", async () => {
  // app1 was paid on ren1 for 2027_H1.
  await renewal("renDup", ["app1"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renDup", FEB_2027), /already_covered/);
  assert.equal(await pay("renDup", "tx-dup", 41667), "rejected");
  assert.equal((await db.doc("delegate_requests/renDup").get()).get("paymentError"), "already_covered");

  // Two pending requests for the same unpaid uid: the first quote wins.
  await lateAppAdded("app5");
  await renewal("renPendA", ["app5"]);
  await J.quoteSubscriptionRequest(db, "renPendA", FEB_2027);
  await renewal("renPendB", ["app5"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renPendB", FEB_2027), /already_covered/);

  // Cancelling the first request frees the uid for a retry.
  await db.doc("delegate_requests/renPendA").update({status: "cancelled"});
  const q = await J.quoteSubscriptionRequest(db, "renPendB", FEB_2027);
  assert.equal(q.amountCents, 41667);

  // A failed payment also allows a later request to quote the same uid.
  assert.equal(await pay("renPendB", "tx-pend-fail", 41667, false), "failed");
  await renewal("renPendC", ["app5"]);
  const q2 = await J.quoteSubscriptionRequest(db, "renPendC", FEB_2027);
  assert.equal(q2.amountCents, 41667);
});

test("staff reject sets a terminal payment status and frees the coverage for a new renewal", async () => {
  await lateAppAdded("app6");
  await renewal("renReject", ["app6"]);
  await J.quoteSubscriptionRequest(db, "renReject", FEB_2027);
  await J.finalizeTerminalRenewal(db, "renReject", "staff_rejected");
  const rejected = (await db.doc("delegate_requests/renReject").get()).data();
  assert.equal(rejected.status, "rejected");
  assert.equal(rejected.paymentStatus, "failed");
  assert.equal(rejected.paymentError, "staff_rejected");
  const cov = (await db.doc("subscription_coverage/2027_H1_app6").get()).data();
  assert.equal(cov.status, "failed");

  await renewal("renRejectRetry", ["app6"]);
  const q = await J.quoteSubscriptionRequest(db, "renRejectRetry", FEB_2027);
  assert.equal(q.amountCents, 41667);
});

test("abandoned pending renewals expire at quote-month end and free their delegates", async () => {
  await lateAppAdded("app7");
  const jan = L.cairoMidnight(2027, 1, 15);
  await renewal("renAbandon", ["app7"]);
  await J.quoteSubscriptionRequest(db, "renAbandon", jan);
  const before = (await db.doc("delegate_requests/renAbandon").get()).data();
  assert.equal(before.paymentStatus, "pending");

  const res = await J.expireAbandonedRenewals(db, FEB_2027);
  assert.ok(res.expired >= 1);
  const expired = (await db.doc("delegate_requests/renAbandon").get()).data();
  assert.equal(expired.paymentStatus, "expired");
  assert.equal(expired.paymentError, "expired");
  assert.equal(expired.status, "expired");
  const cov = (await db.doc("subscription_coverage/2027_H1_app7").get()).data();
  assert.equal(cov.status, "failed");

  await renewal("renAbandonRetry", ["app7"]);
  const q = await J.quoteSubscriptionRequest(db, "renAbandonRetry", FEB_2027);
  assert.equal(q.amountCents, 41667);
});


test("paid add-to-another-chain keeps one subscription across chains", async () => {
  await lateAppAdded("app8");
  await db.doc(delegatePath("o1", "app8")).set({
    uid: "app8", status: "active", companyUID: "c1",
    holds: {subscription_expired: {at: "2027-01-01T00:05:00.000Z", by: "system", source: "suspendExpiredSubscriptions", periodCode: "2027_H1"}},
  });
  await renewal("renAddChain", ["app8"]);
  await J.quoteSubscriptionRequest(db, "renAddChain", FEB_2027);
  assert.equal(await pay("renAddChain", "tx-add-chain", 41667), "paid");
  assert.equal(await expiryHold("o1", "app8"), null);
  assert.equal(await status("o1", "app8"), "active");

  // New chain, no new payment: coverage is still the paid renewal for this uid.
  await db.doc("delegate_requests/addOrgApp8").set({
    requestType: "add_organization", status: "approved", supervisorUid: "sup1",
    companyUID: "c1", organizationUID: "o3", existingDelegateUid: "app8",
    paymentStatus: "not_required", fee: 0, amountDue: 0, periodCode: "2027_H1",
  });
  await db.doc(delegatePath("o3", "app8")).set({
    uid: "app8", status: "active", companyUID: "c1",
    subscription: {periodCode: "2027_H1", paymentStatus: "paid", amountDue: 416.67, renewalRequestId: "renAddChain"},
  });

  const res = await J.runSubscriptionSuspension(db, new Date(Date.UTC(2027, 1, 13, 10)));
  assert.ok(res.covered >= 1);
  assert.equal(await status("o1", "app8"), "active");
  assert.equal(await status("o3", "app8"), "active");

  // A second renewal for the same uid is blocked: one subscription, not per chain.
  await renewal("renAddChainDup", ["app8"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renAddChainDup", FEB_2027), /already_covered/);
});

test("adding a chain does not itself grant coverage to an unpaid delegate", async () => {
  await lateAppAdded("app9");
  await db.doc(delegatePath("o1", "app9")).set({
    uid: "app9", status: "active", companyUID: "c1",
    holds: {subscription_expired: {at: "2027-01-01T00:05:00.000Z", by: "system", source: "suspendExpiredSubscriptions", periodCode: "2027_H1"}},
  });
  await db.doc("delegate_requests/addOrgApp9").set({
    requestType: "add_organization", status: "approved", supervisorUid: "sup1",
    companyUID: "c1", organizationUID: "o3", existingDelegateUid: "app9",
    paymentStatus: "not_required", fee: 0, amountDue: 0, periodCode: "2027_H1",
  });
  // Even if a new chain doc were written as active, the daily job treats
  // coverage per uid from paid/waived requests, not from add_organization.
  await db.doc(delegatePath("o3", "app9")).set({
    uid: "app9", status: "active", companyUID: "c1",
  });
  const res = await J.runSubscriptionSuspension(db, new Date(JAN15_2027.getTime() + 60 * 60 * 1000));
  assert.ok(res.suspendedDocs >= 1); // o3 was written active without coverage
  assert.ok(await expiryHold("o1", "app9"));
  assert.ok(await expiryHold("o3", "app9"));
});

test("late finalize on a rejected request does not overwrite a newer coverage claim", async () => {
  await lateAppAdded("appHold1");
  await renewal("renHoldOld", ["appHold1"]);
  await J.quoteSubscriptionRequest(db, "renHoldOld", FEB_2027);
  await J.finalizeTerminalRenewal(db, "renHoldOld", "staff_rejected");
  await renewal("renHoldNew", ["appHold1"]);
  await J.quoteSubscriptionRequest(db, "renHoldNew", FEB_2027);
  assert.equal((await db.doc("subscription_coverage/2027_H1_appHold1").get()).get("requestId"), "renHoldNew");

  // Same path as the status trigger: rejected → cancelled re-fires finalize.
  const before = (await db.doc("delegate_requests/renHoldOld").get()).data();
  await db.doc("delegate_requests/renHoldOld").update({status: "cancelled"});
  const after = (await db.doc("delegate_requests/renHoldOld").get()).data();
  await J.finalizeRenewalOnStatusChange(db, "renHoldOld", before, after);
  const cov = (await db.doc("subscription_coverage/2027_H1_appHold1").get()).data();
  assert.equal(cov.requestId, "renHoldNew");
  assert.equal(cov.status, "pending");

  await renewal("renHoldThird", ["appHold1"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renHoldThird", FEB_2027), /already_covered/);
});

test("late failed Paymob callback does not overwrite a newer coverage claim", async () => {
  await lateAppAdded("appHold2");
  await renewal("renPayOld", ["appHold2"]);
  await J.quoteSubscriptionRequest(db, "renPayOld", FEB_2027);
  await J.finalizeTerminalRenewal(db, "renPayOld", "staff_rejected");
  await renewal("renPayNew", ["appHold2"]);
  await J.quoteSubscriptionRequest(db, "renPayNew", FEB_2027);
  assert.equal(await pay("renPayOld", "tx-late-fail", 41667, false), "failed");
  const cov = (await db.doc("subscription_coverage/2027_H1_appHold2").get()).data();
  assert.equal(cov.requestId, "renPayNew");
  await renewal("renPayThird", ["appHold2"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renPayThird", FEB_2027), /already_covered/);
});

test("a paid renewal still blocks coverage after its status is cancelled", async () => {
  await lateAppAdded("appHold3");
  await renewal("renPaidCancel", ["appHold3"]);
  await J.quoteSubscriptionRequest(db, "renPaidCancel", FEB_2027);
  assert.equal(await pay("renPaidCancel", "tx-paid-cancel", 41667), "paid");
  await db.doc("delegate_requests/renPaidCancel").update({status: "cancelled"});
  await renewal("renPaidCancelRetry", ["appHold3"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renPaidCancelRetry", FEB_2027), /already_covered/);
  const before = {status: "approved", paymentStatus: "paid", requestType: "renewal"};
  const after = {status: "cancelled", paymentStatus: "paid", requestType: "renewal"};
  await J.finalizeRenewalOnStatusChange(db, "renPaidCancel", before, after);
  assert.equal((await db.doc("delegate_requests/renPaidCancel").get()).get("paymentStatus"), "paid");
});

test("partial-duplicate remaining chains attach to the existing uid with no new fee", async () => {
  await lateAppAdded("dlgExist");
  await db.doc(delegatePath("o1", "dlgExist")).set({
    uid: "dlgExist", status: "active", companyUID: "c1",
    nationalId: "20000000000099", phoneNumber: "01000000099",
    subscription: {periodCode: "2027_H1", paymentStatus: "paid", amountDue: 416.67, renewalRequestId: "ren-exist"},
  });
  await db.doc("delegate_requests/ren-exist").set({
    requestType: "renewal", status: "approved", paymentStatus: "paid",
    supervisorUid: "sup1", companyUID: "c1", organizationUID: "o1",
    periodCode: "2027_H1", coveredDelegateUids: ["dlgExist"], amountDue: 416.67,
  });
  await db.doc("subscription_coverage/2027_H1_dlgExist").set({
    requestId: "ren-exist", uid: "dlgExist", periodCode: "2027_H1", status: "paid",
  });

  await db.doc("delegate_requests/addExistRest").set({
    requestType: "add_organization", status: "approved", supervisorUid: "sup1",
    companyUID: "c1", organizationUID: "o3", organizationUIDs: ["o3"],
    existingDelegateUid: "dlgExist",
    paymentStatus: "not_required", fee: 0, amountDue: 0, periodCode: "2027_H1",
  });
  await db.doc(delegatePath("o3", "dlgExist")).set({
    uid: "dlgExist", status: "active", companyUID: "c1",
    subscription: {periodCode: "2027_H1", paymentStatus: "paid", amountDue: 416.67, renewalRequestId: "ren-exist"},
  });
  const addReq = (await db.doc("delegate_requests/addExistRest").get()).data();
  assert.equal(addReq.existingDelegateUid, "dlgExist");
  assert.equal(addReq.fee, 0);
  assert.equal(addReq.paymentStatus, "not_required");
  assert.equal((await db.doc(delegatePath("o3", "dlgExist")).get()).get("uid"), "dlgExist");
  await renewal("renExistDup", ["dlgExist"]);
  await assert.rejects(J.quoteSubscriptionRequest(db, "renExistDup", FEB_2027), /already_covered/);
});

test("advance renewal: next-period quote is 500 and does not clear an expiry hold before Jan 1", async () => {
  const dec = L.cairoMidnight(2026, 12, 15);
  await lateAppAdded("appAdv1");
  await db.doc(delegatePath("o1", "appAdv1")).set({
    uid: "appAdv1", status: "suspended", companyUID: "c1",
    statusReason: "subscription_expired",
    subscription: {periodCode: "2026_H2", paymentStatus: "paid", amountDue: 0},
    holds: {subscription_expired: {
      at: "2026-07-01T00:05:00.000Z", by: "system",
      source: "suspendExpiredSubscriptions", periodCode: "2026_H2",
    }},
  });
  await db.doc("delegate_requests/renAdv1").set({
    requestType: "renewal", status: "pending", supervisorUid: "sup1", companyUID: "c1",
    organizationUID: "o1", periodCode: "2027_H1", paymentStatus: "pending",
    coveredDelegateUids: ["appAdv1"], items: [{uid: "appAdv1", fee: 500}], amountDue: 500,
  });

  await db.doc("config/subscriptions").set({advanceRenewalEnabled: false, advanceRenewalDays: 30});
  await assert.rejects(J.quoteSubscriptionRequest(db, "renAdv1", dec), /period_mismatch/);

  await db.doc("config/subscriptions").set({advanceRenewalEnabled: true, advanceRenewalDays: 30});
  const q = await J.quoteSubscriptionRequest(db, "renAdv1", dec);
  assert.equal(q.periodCode, "2027_H1");
  assert.equal(q.amount, 500);
  assert.equal(q.amountCents, 50000);
  assert.equal(q.remainingMonths, 6);

  // A current-period quote in Dec 2026 is still refused as free (the flag
  // only opens the next period; it does not make a 0 EGP current quote payable).
  await db.doc("delegate_requests/renAdvCurrent").set({
    requestType: "renewal", status: "pending", supervisorUid: "sup1", companyUID: "c1",
    organizationUID: "o1", periodCode: "2026_H2", paymentStatus: "pending",
    coveredDelegateUids: ["appAdv1"], items: [{uid: "appAdv1", fee: 0}], amountDue: 0,
  });
  await assert.rejects(J.quoteSubscriptionRequest(db, "renAdvCurrent", dec), /free_period/);
  await db.doc("delegate_requests/renAdvCurrent").update({status: "cancelled"});

  assert.equal(await J.applyVerifiedSubscriptionPayment(db, {
    requestId: "renAdv1", paymobTransactionId: "tx-adv-1", paymobOrderId: "o-adv-1",
    success: true, amountCents: 50000, currency: "EGP", paidAt: dec,
  }), "paid");
  const d = (await db.doc(delegatePath("o1", "appAdv1")).get()).data();
  assert.equal(d.status, "suspended", "must not reactivate before the paid period starts");
  assert.equal(d.statusReason, "subscription_expired");
  assert.ok(d.holds && d.holds.subscription_expired);
  assert.equal(d.subscription.periodCode, "2026_H2", "current subscription must be preserved");
  assert.equal(d.subscription.paymentStatus, "paid");
  assert.equal(d.nextSubscription.periodCode, "2027_H1");
  assert.equal(d.nextSubscription.paymentStatus, "paid");
});

test("advance renewal: during January grace M1 skips prepaid uids and clears a leftover expiry hold", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN1_2027.getTime() + 2 * 60 * 60 * 1000));
  assert.equal(res.skipped, "grace_period");
  assert.ok((res.clearedHolds || 0) >= 1, `clearedHolds=${res.clearedHolds}`);
  const d = (await db.doc(delegatePath("o1", "appAdv1")).get()).data();
  assert.equal(d.holds && d.holds.subscription_expired, undefined);
  // Shadow M1 now matches M2: once the expiry hold is gone and the paid
  // period is promoted, the leftover expiry status is cleared.
  assert.equal(d.status, "active");
  assert.equal(d.statusReason, undefined);
  assert.equal(d.subscription.periodCode, "2027_H1");
  assert.equal(d.nextSubscription, undefined);
  await db.doc("config/subscriptions").delete();
});

test("shadow paid renewal reactivates a legacy-suspended delegate when no holds remain", async () => {
  await lateAppAdded("appShadowRe");
  await db.doc(delegatePath("o1", "appShadowRe")).set({
    uid: "appShadowRe", status: "suspended", companyUID: "c1",
    statusReason: "subscription_expired",
    holds: {subscription_expired: {
      at: "2027-01-01T00:05:00.000Z", by: "system",
      source: "suspendExpiredSubscriptions", periodCode: "2027_H1",
    }},
  });
  await renewal("renShadowRe", ["appShadowRe"]);
  const q = await J.quoteSubscriptionRequest(db, "renShadowRe", FEB_2027);
  assert.equal(await J.applyVerifiedSubscriptionPayment(db, {
    requestId: "renShadowRe", paymobTransactionId: "tx-shadow-re",
    paymobOrderId: "o-shadow-re", success: true, amountCents: q.amountCents,
    currency: "EGP", paidAt: FEB_2027,
  }), "paid");
  const d = (await db.doc(delegatePath("o1", "appShadowRe")).get()).data();
  assert.equal(d.holds && d.holds.subscription_expired, undefined);
  assert.equal(d.status, "active");
  assert.equal(d.statusReason, undefined);
  assert.equal(d.subscription.periodCode, "2027_H1");
  assert.equal(d.subscription.paymentStatus, "paid");
});

test("paid renewal does not reactivate a legacy admin_suspend with no holds map", async () => {
  await lateAppAdded("d_legacy_admin_nohold");
  await db.doc(delegatePath("o1", "d_legacy_admin_nohold")).set({
    uid: "d_legacy_admin_nohold", status: "suspended", companyUID: "c1",
    statusReason: "admin_suspend",
  });
  await renewal("renLegacyAdmin", ["d_legacy_admin_nohold"]);
  const q = await J.quoteSubscriptionRequest(db, "renLegacyAdmin", FEB_2027);
  assert.equal(await J.applyVerifiedSubscriptionPayment(db, {
    requestId: "renLegacyAdmin", paymobTransactionId: "tx-legacy-admin",
    paymobOrderId: "o-legacy-admin", success: true, amountCents: q.amountCents,
    currency: "EGP", paidAt: FEB_2027,
  }), "paid");
  const d = (await db.doc(delegatePath("o1", "d_legacy_admin_nohold")).get()).data();
  assert.equal(d.status, "suspended");
  assert.equal(d.statusReason, "admin_suspend");
  assert.equal(d.subscription.periodCode, "2027_H1");
  assert.equal(d.subscription.paymentStatus, "paid");
});

test("paid renewal does not reactivate a legacy device_unbind suspension with no holds map", async () => {
  await lateAppAdded("d_legacy_unbind_nohold");
  await db.doc(delegatePath("o1", "d_legacy_unbind_nohold")).set({
    uid: "d_legacy_unbind_nohold", status: "suspended", companyUID: "c1",
    statusReason: "device_unbind",
  });
  await renewal("renLegacyUnbind", ["d_legacy_unbind_nohold"]);
  const q = await J.quoteSubscriptionRequest(db, "renLegacyUnbind", FEB_2027);
  assert.equal(await J.applyVerifiedSubscriptionPayment(db, {
    requestId: "renLegacyUnbind", paymobTransactionId: "tx-legacy-unbind",
    paymobOrderId: "o-legacy-unbind", success: true, amountCents: q.amountCents,
    currency: "EGP", paidAt: FEB_2027,
  }), "paid");
  const d = (await db.doc(delegatePath("o1", "d_legacy_unbind_nohold")).get()).data();
  assert.equal(d.status, "suspended");
  assert.equal(d.statusReason, "device_unbind");
  assert.equal(d.subscription.periodCode, "2027_H1");
  assert.equal(d.subscription.paymentStatus, "paid");
});

test("M1 period-start promotion does not reactivate a legacy admin_suspend", async () => {
  await lateAppAdded("d_m1_legacy_admin");
  await db.doc("delegate_requests/renM1LegacyAdmin").set({
    requestType: "renewal", status: "approved", paymentStatus: "paid",
    supervisorUid: "sup1", companyUID: "c1", organizationUID: "o1",
    periodCode: "2027_H1", coveredDelegateUids: ["d_m1_legacy_admin"],
    items: [{uid: "d_m1_legacy_admin", fee: 500}], amountDue: 500,
  });
  await db.doc(delegatePath("o1", "d_m1_legacy_admin")).set({
    uid: "d_m1_legacy_admin", status: "suspended", companyUID: "c1",
    statusReason: "admin_suspend",
    subscription: {periodCode: "2026_H2", paymentStatus: "paid", amountDue: 0},
    nextSubscription: {periodCode: "2027_H1", paymentStatus: "paid", amountDue: 500},
  });
  await J.runSubscriptionSuspension(db, new Date(JAN1_2027.getTime() + 3 * 60 * 60 * 1000));
  const d = (await db.doc(delegatePath("o1", "d_m1_legacy_admin")).get()).data();
  assert.equal(d.status, "suspended");
  assert.equal(d.statusReason, "admin_suspend");
  assert.equal(d.subscription.periodCode, "2027_H1");
  assert.equal(d.nextSubscription, undefined);
});

test("subscription reminder targets company supervisor inbox, not request creator", async () => {
  await db.doc("users/hr1").set({
    role: "hr", organizationUID: "o1", companyUID: "c1", displayName: "HR One",
  });
  await db.doc("delegate_requests/app_hr").set({
    requestType: "new_delegate", status: "approved", supervisorUid: "hr1", companyUID: "c1",
    organizationUID: "o1", periodCode: "2026_H2", paymentStatus: "waived",
  });
  await db.doc(delegatePath("o1", "app_hr")).set({uid: "app_hr", status: "active", companyUID: "c1"});

  const jun16 = L.cairoMidnight(2027, 6, 16);
  const res = await J.runSubscriptionReminders(db, jun16);
  assert.ok(res.notifications >= 1);

  const inbox = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("companyUID", "==", "c1")
    .where("delegateUid", "==", "sup1")
    .get();
  const hrMis = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("delegateUid", "==", "hr1")
    .get();
  assert.equal(hrMis.size, 0);
  assert.ok(inbox.size >= 1);
});

test("subscription reminder fans out to supervisors across org chains for one company", async () => {
  await db.doc("users/sup_o1").set({
    role: "supervisor", organizationUID: "o1", companyUID: "c_2org", status: "active",
  });
  await db.doc("users/sup_o2").set({
    role: "supervisor", organizationUID: "o2", companyUID: "c_2org", status: "active",
  });
  for (const [id, org] of [["d_o1", "o1"], ["d_o2", "o2"]]) {
    await db.doc(`delegate_requests/req_${id}`).set({
      requestType: "new_delegate", status: "approved", supervisorUid: "sup_o1",
      companyUID: "c_2org", organizationUID: org, periodCode: "2026_H2", paymentStatus: "waived",
    });
    await db.doc(`organizations/${org}/companies/c_2org/delegates/${id}`).set({
      uid: id, status: "active", companyUID: "c_2org", registeredVia: "mobile_app",
    });
  }
  const jun16 = L.cairoMidnight(2027, 6, 16);
  await db.doc("subscription_reminder_runs/2027_H1_2027-06-16").delete();
  await J.runSubscriptionReminders(db, jun16);
  for (const uid of ["sup_o1", "sup_o2"]) {
    const snap = await db.collection("notifications")
      .where("type", "==", "subscription_renewal_reminder")
      .where("delegateUid", "==", uid)
      .where("companyUID", "==", "c_2org")
      .get();
    assert.equal(snap.size, 1, uid);
    assert.equal(snap.docs[0].get("uncoveredDelegateCount"), 2);
  }
});

test("subscription reminder one per supervisor when requests mix organizationUID", async () => {
  await db.doc("users/sup_one").set({
    role: "supervisor", organizationUID: "o1", companyUID: "c_mix", status: "active",
  });
  for (const id of ["mix_a", "mix_b", "mix_c"]) {
    const extra = id === "mix_a" ? {organizationUID: "o1"} : {};
    await db.doc(`delegate_requests/req_${id}`).set({
      requestType: "new_delegate", status: "approved", supervisorUid: "sup_one",
      companyUID: "c_mix", periodCode: "2026_H2", paymentStatus: "waived", ...extra,
    });
    await db.doc(`organizations/o1/companies/c_mix/delegates/${id}`).set({
      uid: id, status: "active", companyUID: "c_mix", registeredVia: "mobile_app",
    });
  }
  const jun16 = L.cairoMidnight(2027, 6, 16);
  await db.doc("subscription_reminder_runs/2027_H1_2027-06-16").delete();
  await J.runSubscriptionReminders(db, jun16);
  const snap = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("delegateUid", "==", "sup_one")
    .where("companyUID", "==", "c_mix")
    .get();
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].get("uncoveredDelegateCount"), 3);
});

test("subscription reminder fans out to every live company supervisor", async () => {
  await db.doc("users/sup_b").set({
    role: "company_supervisor", organizationUID: "o1", companyUID: "c1", status: "active",
  });
  await db.doc("users/sup_inact").set({
    role: "supervisor", organizationUID: "o1", companyUID: "c1", isActive: false,
  });
  const jun16 = L.cairoMidnight(2027, 6, 16);
  await db.doc("subscription_reminder_runs/2027_H1_2027-06-16").delete();
  const res = await J.runSubscriptionReminders(db, jun16);
  assert.ok(res.notifications >= 1);
  for (const uid of ["sup1", "sup_b"]) {
    const snap = await db.collection("notifications")
      .where("type", "==", "subscription_renewal_reminder")
      .where("companyUID", "==", "c1")
      .where("delegateUid", "==", uid)
      .get();
    assert.ok(snap.size >= 1, uid);
  }
  const inactiveMis = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("delegateUid", "==", "sup_inact")
    .get();
  assert.equal(inactiveMis.size, 0);
});

test("subscription reminder uses replacement supervisor when request creator uid is stale", async () => {
  await db.doc("users/old_sup").set({
    role: "hr", organizationUID: "o1", companyUID: "c1", status: "active",
  });
  await db.doc("users/sup_repl").set({
    role: "supervisor", organizationUID: "o1", companyUID: "c1", status: "active",
  });
  await db.doc("delegate_requests/stale_sup").set({
    requestType: "new_delegate", status: "approved", supervisorUid: "old_sup", companyUID: "c1",
    organizationUID: "o1", periodCode: "2026_H2", paymentStatus: "waived",
  });
  await db.doc(delegatePath("o1", "stale_sup")).set({uid: "stale_sup", status: "active", companyUID: "c1"});

  const jun16 = L.cairoMidnight(2027, 6, 16);
  await db.doc("subscription_reminder_runs/2027_H1_2027-06-16").delete();
  await J.runSubscriptionReminders(db, jun16);

  const oldMis = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("delegateUid", "==", "old_sup")
    .get();
  assert.equal(oldMis.size, 0);
  const repl = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("delegateUid", "==", "sup_repl")
    .get();
  assert.ok(repl.size >= 1);
});

test("July grace then suspension on the 15th for H2", async () => {
  const jul1 = L.cairoMidnight(2027, 7, 1);
  const grace = await J.runSubscriptionSuspension(db, new Date(jul1.getTime() + 60 * 60 * 1000));
  assert.equal(grace.skipped, "grace_period");
  const jul15 = await J.runSubscriptionSuspension(db, new Date(JUL15_2027.getTime() + 60 * 60 * 1000));
  assert.equal(jul15.periodCode, "2027_H2");
  assert.ok(jul15.suspendedDocs >= 1);
});

test("supervisor reminder on 16 Jun for H1 end (default 14 days)", async () => {
  const jun16 = L.cairoMidnight(2027, 6, 16);
  const res = await J.runSubscriptionReminders(db, jun16);
  assert.equal(res.skipped, undefined);
  assert.equal(res.endingPeriodCode, "2027_H1");
  assert.equal(res.nextPeriodCode, "2027_H2");
  assert.ok(res.notifications >= 1);
  const notifs = await db.collection("notifications")
    .where("type", "==", "subscription_renewal_reminder")
    .where("delegateUid", "==", "sup1")
    .get();
  assert.ok(notifs.size >= 1);
  const body = notifs.docs[0].get("body");
  assert.match(body, /تذكير|تجديد/);
});

test("reminder skipped on non-reminder day", async () => {
  const jun10 = L.cairoMidnight(2027, 6, 10);
  const res = await J.runSubscriptionReminders(db, jun10);
  assert.equal(res.skipped, "not_reminder_day");
});

test("Dec 17 2026 reminds for 2027_H1 even though today is still free promo", async () => {
  const dec17 = L.cairoMidnight(2026, 12, 17);
  const res = await J.runSubscriptionReminders(db, dec17);
  assert.notEqual(res.skipped, "free_promotion");
  assert.equal(res.endingPeriodCode, "2026_H2");
  assert.equal(res.nextPeriodCode, "2027_H1");
  assert.ok(res.notifications >= 1);
});

test("Jun 16 2026 skips reminder because upcoming 2026_H2 is still free", async () => {
  const jun16 = L.cairoMidnight(2026, 6, 16);
  const res = await J.runSubscriptionReminders(db, jun16);
  assert.equal(res.skipped, "free_promotion");
  assert.equal(res.nextPeriodCode, "2026_H2");
});

test("40 companies on reminder day: one notification per live supervisor, idempotent rerun", async () => {
  const n = 40;
  const jun16 = L.cairoMidnight(2027, 6, 16);
  const runId = "2027_H1_2027-06-16";
  await db.doc(`subscription_reminder_runs/${runId}`).delete();

  for (let i = 0; i < n; i++) {
    const co = `c_bulk_${i}`;
    await db.doc(`users/sup_bulk_${i}`).set({
      role: i % 3 === 0 ? "company-supervisor" : "supervisor",
      organizationUID: "o1",
      companyUID: co,
      status: "active",
    });
    await db.doc(`delegate_requests/bulk_req_${i}`).set({
      requestType: "new_delegate",
      status: "approved",
      supervisorUid: `sup_bulk_${i}`,
      companyUID: co,
      organizationUID: "o1",
      periodCode: "2026_H2",
      paymentStatus: "waived",
    });
    await db.doc(`organizations/o1/companies/c1/delegates/bulk_${i}`).set({
      uid: `bulk_${i}`,
      status: "active",
      companyUID: co,
      registeredVia: "mobile_app",
    });
  }

  const res = await J.runSubscriptionReminders(db, jun16);
  assert.ok(res.companies >= n);
  assert.ok(res.supervisors >= n);
  assert.ok(res.notifications >= n);

  for (let i = 0; i < n; i++) {
    const snap = await db.collection("notifications")
      .where("type", "==", "subscription_renewal_reminder")
      .where("delegateUid", "==", `sup_bulk_${i}`)
      .get();
    assert.equal(snap.size, 1, `sup_bulk_${i}`);
  }

  const res2 = await J.runSubscriptionReminders(db, jun16);
  assert.equal(res2.notifications, res.notifications);
  assert.equal(res2.supervisors, res.supervisors);
  for (let i = 0; i < n; i++) {
    const snap = await db.collection("notifications")
      .where("type", "==", "subscription_renewal_reminder")
      .where("delegateUid", "==", `sup_bulk_${i}`)
      .get();
    assert.equal(snap.size, 1, `rerun sup_bulk_${i}`);
  }
});


