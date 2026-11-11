/**
 * Subscription suspension + Paymob payment hook against the Firestore emulator.
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
  // A company in another org: c2 for wrong-company checks.
  await db.doc("delegate_requests/other").set({
    requestType: "new_delegate", status: "approved", supervisorUid: "sup2", companyUID: "c2",
  });
  await db.doc("organizations/o1/companies/c2/delegates/other").set({uid: "other", status: "active", companyUID: "c2"});
}

const status = async (org, uid) => (await db.doc(delegatePath(org, uid)).get()).get("status");

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

test("period end: app-added delegates suspended in every chain; web, manual and pending untouched", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN1_2027.getTime() + 5 * 60 * 1000));
  assert.equal(res.periodCode, "2027_H1");
  assert.equal(res.suspendedDocs, 5); // app1 x2, app2, app3, other (company c2)
  assert.equal(res.suspendedUsers, 1);
  for (const [o, u] of [["o1", "app1"], ["o2", "app1"], ["o1", "app2"], ["o1", "app3"]]) {
    assert.equal(await status(o, u), "suspended", `${o}/${u}`);
    const d = (await db.doc(delegatePath(o, u)).get()).data();
    assert.equal(d.statusReason, "subscription_expired");
    assert.equal(d.subscription.suspendedForPeriod, "2027_H1");
  }
  assert.equal(await status("o1", "web1"), "active");
  assert.equal(await status("o2", "web2"), "active");
  assert.equal((await db.doc(delegatePath("o1", "manual")).get()).get("statusReason"), "manual");
  assert.equal(await status("o1", "pend"), "pending");
  assert.equal((await db.doc("users/app1").get()).get("status"), "suspended");
  assert.equal((await db.doc("users/web1").get()).get("status"), "active");
  const runs = await db.collection("subscription_suspension_runs").get();
  assert.equal(runs.size, 1);
});

test("idempotent: a second run changes nothing", async () => {
  const res = await J.runSubscriptionSuspension(db, new Date(JAN1_2027.getTime() + 60 * 60 * 1000));
  assert.equal(res.suspendedDocs, 0);
  assert.equal(res.suspendedUsers, 0);
  assert.equal(res.alreadySuspended, 6); // 5 + the manual one
});

async function renewal(id, uids, extra = {}) {
  const fee = L.feeAt(FEB_2027);
  await db.doc(`delegate_requests/${id}`).set({
    requestType: "renewal", status: "pending", supervisorUid: "sup1", companyUID: "c1",
    periodCode: "2027_H1", paymentStatus: "pending", coveredDelegateUids: uids,
    items: uids.map((uid) => ({uid, fee})), amountDue: L.roundMoney(fee * uids.length), ...extra,
  });
}
const pay = (requestId, tx, amountCents, success = true) => J.applyVerifiedSubscriptionPayment(db, {
  requestId, paymobTransactionId: tx, paymobOrderId: `o-${tx}`, success, amountCents, currency: "EGP", paidAt: FEB_2027,
});

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
  const jan = L.cairoMidnight(2027, 1, 15);
  await renewal("renStale", ["app1"], {
    amountDue: L.feeAt(jan),
    fee: L.feeAt(jan),
    remainingMonths: 6,
    items: [{uid: "app1", fullName: "App One", fee: L.feeAt(jan)}],
  });
  const q = await J.quoteSubscriptionRequest(db, "renStale", FEB_2027);
  assert.equal(q.amount, 416.67);
  assert.equal(q.remainingMonths, 5);
  const stored = (await db.doc("delegate_requests/renStale").get()).data();
  assert.equal(stored.amountDue, 416.67);
  assert.equal(stored.fee, 416.67);
  assert.equal(stored.remainingMonths, 5);
  assert.equal(stored.items[0].fee, 416.67);
  assert.equal(stored.items[0].fullName, "App One");
});

test("failed payment: nobody is reactivated; retry allowed", async () => {
  assert.equal(await pay("ren1", "tx-fail", 83334, false), "failed");
  const r = (await db.doc("delegate_requests/ren1").get()).data();
  assert.equal(r.paymentStatus, "failed");
  assert.equal(await status("o1", "app1"), "suspended");
  assert.equal(await status("o1", "app2"), "suspended");
});

test("wrong amount is rejected for review and activates nobody", async () => {
  assert.equal(await pay("ren1", "tx-short", 100), "rejected");
  const r = (await db.doc("delegate_requests/ren1").get()).data();
  assert.equal(r.paymentError, "amount_mismatch");
  assert.equal(r.needsReview, true);
  assert.equal(await status("o1", "app1"), "suspended");
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
    assert.equal(d.subscription.periodCode, "2027_H1");
    assert.equal(d.subscription.periodStart, "2027-01-01");
    assert.equal(d.subscription.periodEnd, "2027-06-30");
    assert.equal(d.subscription.amountDue, 416.67);
    assert.equal(d.subscription.paymentStatus, "paid");
    assert.equal(d.subscription.renewalRequestId, "ren1");
  }
  assert.equal(await status("o1", "app3"), "suspended"); // not selected: renew later
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
  assert.equal(await status("o1", "app1"), "active");
  assert.equal(await status("o1", "app3"), "suspended");
});

test("client-forced reactivation without payment is undone by the next run", async () => {
  await db.doc(delegatePath("o1", "app3")).update({status: "active"});
  const res = await J.runSubscriptionSuspension(db, new Date(Date.UTC(2027, 1, 12, 10)));
  assert.equal(res.suspendedDocs, 1);
  assert.equal(await status("o1", "app3"), "suspended");
});

test("renewing the rest later: second partial renewal", async () => {
  await renewal("ren2", ["app3"]);
  const q = await J.quoteSubscriptionRequest(db, "ren2", FEB_2027);
  assert.equal(q.amountCents, 41667);
  assert.equal(await pay("ren2", "tx-2", 41667), "paid");
  assert.equal(await status("o1", "app3"), "active");
});
