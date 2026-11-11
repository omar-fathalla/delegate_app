"use strict";

/**
 * Paymob group-renewal scenario matrix. Webhooks are HMAC-signed with a
 * fake secret; no real Paymob keys are used.
 */
const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");
const path = require("path");
const {MemoryFirestore, Timestamp} = require("./helpers/memory_firestore");

process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "test-project";
process.env.HOLDS_AUTHORITY_MODE = process.env.HOLDS_AUTHORITY_MODE || "shadow";

const hmac = require(path.join(__dirname, "../lib/paymob_hmac.js"));
const paymob = require(path.join(__dirname, "../lib/paymob_subscription.js"));
const jobs = require(path.join(__dirname, "../lib/subscription_jobs.js"));

const SECRET = "test-hmac-secret-not-real";
const AT = new Date("2027-02-10T10:00:00.000Z"); // Cairo noon Feb 10: 5 months, 416.67
const FEE = 416.67;
const CENTS = 41667;

function sampleObj(overrides = {}) {
  return {
    amount_cents: CENTS,
    created_at: "2027-02-10T10:00:00.000000",
    currency: "EGP",
    error_occured: false,
    has_parent_transaction: false,
    id: 1001,
    integration_id: 4097558,
    is_3d_secure: true,
    is_auth: false,
    is_capture: false,
    is_refunded: false,
    is_standalone_payment: true,
    is_voided: false,
    order: {id: 5001, merchant_order_id: "ren1"},
    owner: 302852,
    pending: false,
    source_data: {pan: "2346", sub_type: "MasterCard", type: "card"},
    success: true,
    ...overrides,
  };
}

function sign(obj) {
  return crypto.createHmac("sha512", SECRET)
    .update(hmac.transactionPostHmacPayload(obj))
    .digest("hex");
}

async function seed({
  db,
  requestId = "ren1",
  uids = ["d1"],
  paymentStatus = "pending",
  status = "pending",
  quotedAt = AT,
  checkoutAt = null,
  companyUID = "co1",
} = {}) {
  await db.doc("users/sup1").set({
    role: "super-admin",
    organizationUID: "org1",
    companyUID,
  });
  for (const uid of uids) {
    await db.collection("delegate_requests").doc(uid).set({
      requestType: "new_delegate",
      status: "approved",
      supervisorUid: "sup1",
      companyUID,
      organizationUID: "org1",
    });
    await db.doc(`organizations/org1/companies/${companyUID}/delegates/${uid}`).set({
      uid,
      fullName: uid,
      status: "active",
    });
  }
  const data = {
    requestType: "renewal",
    status,
    paymentStatus,
    companyUID,
    organizationUID: "org1",
    supervisorUid: "sup1",
    periodCode: "2027_H1",
    coveredDelegateUids: uids,
    items: uids.map((uid) => ({uid, fee: FEE, fullName: uid})),
    amountDue: FEE * uids.length,
    fee: FEE * uids.length,
    remainingMonths: 5,
    quotedAt: Timestamp.fromDate(quotedAt),
    createdAt: Timestamp.fromDate(quotedAt),
  };
  if (checkoutAt) {
    data.paymobCheckout = {createdAt: Timestamp.fromDate(checkoutAt), amountCents: CENTS * uids.length};
  }
  await db.collection("delegate_requests").doc(requestId).set(data);
  return db;
}

async function webhook(db, overrides = {}) {
  const obj = sampleObj(overrides);
  return paymob.handlePaymobWebhook({
    obj,
    hmac: sign(obj),
    hmacSecret: SECRET,
    db,
    now: AT,
  });
}

async function req(db, id = "ren1") {
  return (await db.collection("delegate_requests").doc(id).get()).data();
}

describe("paymob scenario matrix (fake HMAC, no real keys)", () => {
  let db;
  beforeEach(async () => {
    db = new MemoryFirestore();
    await seed({db});
  });

  it("card declined / insufficient funds marks failed and releases coverage", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {success: false, error_occured: true, id: 2001});
    assert.equal(result.status, 200);
    assert.equal(result.outcome, "failed");
    const r = await req(db);
    assert.equal(r.paymentStatus, "failed");
    assert.equal(r.paymentError, "payment_failed");
    const cov = await db.doc("subscription_coverage/2027_H1_d1").get();
    assert.equal(cov.exists, true);
    assert.equal(cov.get("status"), "failed");
  });

  it("3DS failed is a failed (non-pending) webhook", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {success: false, is_3d_secure: true, id: 2002});
    assert.equal(result.outcome, "failed");
    assert.equal((await req(db)).paymentStatus, "failed");
  });

  it("a verified pending (abandoned 3DS / still open iframe) is ignored", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {pending: true, success: false, id: 2003});
    assert.equal(result.outcome, "ignored_pending");
    assert.equal((await req(db)).paymentStatus, "pending");
  });

  it("success webhook after a charge still applies if it arrives late", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {success: true, id: 3001});
    assert.equal(result.outcome, "paid");
    assert.equal((await req(db)).paymentStatus, "paid");
  });

  it("duplicate HMAC-signed success is idempotent on the Paymob tx id", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const first = await webhook(db, {success: true, id: 3002});
    const second = await webhook(db, {success: true, id: 3002});
    assert.equal(first.outcome, "paid");
    assert.equal(second.outcome, "duplicate");
    assert.equal((await req(db)).paymentStatus, "paid");
  });

  it("a later failed event after success must not unpay the request", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    assert.equal((await webhook(db, {success: true, id: 3003})).outcome, "paid");
    const failed = await webhook(db, {success: false, id: 3999});
    assert.equal(failed.outcome, "ignored_after_paid");
    const r = await req(db);
    assert.equal(r.paymentStatus, "paid");
    assert.equal(r.needsReview, true);
  });

  it("void or refund after paid is flagged for review and does not unpay", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    assert.equal((await webhook(db, {success: true, id: 3004})).outcome, "paid");
    const voided = await webhook(db, {success: true, is_voided: true, id: 4001});
    assert.equal(voided.outcome, "ignored_after_paid");
    const refunded = await webhook(db, {success: true, is_refunded: true, id: 4002});
    assert.equal(refunded.outcome, "ignored_after_paid");
    assert.equal((await req(db)).paymentStatus, "paid");
  });

  it("void of a still-pending transaction marks the request failed", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {success: true, is_voided: true, id: 4003});
    assert.equal(result.outcome, "failed");
    assert.equal((await req(db)).paymentStatus, "failed");
    assert.equal((await req(db)).paymentError, "voided");
  });

  it("amount mismatch fails closed and does not activate anyone", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {success: true, amount_cents: 1, id: 5002});
    assert.equal(result.outcome, "rejected");
    const r = await req(db);
    assert.equal(r.paymentStatus, "failed");
    assert.equal(r.paymentError, "amount_mismatch");
    assert.equal(r.needsReview, true);
  });

  it("currency mismatch fails closed", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const result = await webhook(db, {success: true, currency: "USD", id: 5003});
    assert.equal(result.outcome, "rejected");
    assert.equal((await req(db)).paymentError, "currency_mismatch");
  });

  it("an awaiting request auto-expires after the 60-minute checkout TTL", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const later = new Date(AT.getTime() + 61 * 60 * 1000);
    const res = await jobs.expireAbandonedRenewals(db, later);
    assert.equal(res.expired, 1);
    const r = await req(db);
    assert.equal(r.paymentStatus, "expired");
    const cov = await db.doc("subscription_coverage/2027_H1_d1").get();
    assert.equal(cov.get("status"), "failed");
  });

  it("a late success after TTL expire still marks the original request paid", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    await jobs.expireAbandonedRenewals(db, new Date(AT.getTime() + 61 * 60 * 1000));
    assert.equal((await req(db)).paymentStatus, "expired");
    const result = await webhook(db, {success: true, id: 6001});
    assert.equal(result.outcome, "paid");
    assert.equal((await req(db)).paymentStatus, "paid");
  });

  it("the same request can be retried after failed or expired", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    await webhook(db, {success: false, id: 7001});
    assert.equal((await req(db)).paymentStatus, "failed");
    const again = await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    assert.equal(again.amountCents, CENTS);
    assert.equal((await req(db)).paymentStatus, "pending");
  });

  it("a second renewal is blocked while one is still awaiting payment", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    db = db; // already seeded
    await seed({db, requestId: "ren2", quotedAt: AT});
    await assert.rejects(
      () => jobs.quoteSubscriptionRequest(db, "ren2", AT),
      (e) => e.reason === "already_covered",
    );
  });

  it("a stale awaiting request is released so a new renewal can be quoted", async () => {
    await jobs.quoteSubscriptionRequest(db, "ren1", AT);
    const later = new Date(AT.getTime() + 61 * 60 * 1000);
    await seed({db, requestId: "ren2", quotedAt: later});
    const quote = await jobs.quoteSubscriptionRequest(db, "ren2", later);
    assert.equal(quote.amountCents, CENTS);
    assert.equal((await req(db, "ren1")).paymentStatus, "expired");
  });

  it("a delegate cannot be included in two live requests", async () => {
    await seed({db, requestId: "renA", uids: ["d1", "d2"]});
    await seed({db, requestId: "renB", uids: ["d2", "d3"]});
    await jobs.quoteSubscriptionRequest(db, "renA", AT);
    await assert.rejects(
      () => jobs.quoteSubscriptionRequest(db, "renB", AT),
      (e) => e.reason === "already_covered",
    );
  });

  it("partial success: a deleted delegate is skipped and needsReview is set", async () => {
    await seed({db, requestId: "renP", uids: ["d1", "gone"]});
    // Remove the gone delegate doc only (registration stays so quote can pass).
    db._store.delete("organizations/org1/companies/co1/delegates/gone");
    await jobs.quoteSubscriptionRequest(db, "renP", AT);
    const result = await webhook(db, {
      success: true,
      id: 8001,
      amount_cents: CENTS * 2,
      order: {id: 5001, merchant_order_id: "renP"},
    });
    assert.equal(result.outcome, "paid");
    const r = await req(db, "renP");
    assert.equal(r.paymentStatus, "paid");
    assert.equal(r.needsReview, true);
    assert.equal(r.applyError, "partial_apply");
    assert.deepEqual(r.missingDelegateUids, ["gone"]);
  });

  it("isCheckoutInProgress refuses a double-tap within 20 seconds", () => {
    const now = new Date("2027-02-10T10:00:10.000Z");
    const fresh = {
      paymentStatus: "pending",
      paymobCheckout: {createdAt: new Date("2027-02-10T10:00:00.000Z")},
    };
    const stale = {
      paymentStatus: "pending",
      paymobCheckout: {createdAt: new Date("2027-02-10T09:59:00.000Z")},
    };
    assert.equal(paymob.isCheckoutInProgress(fresh, now), true);
    assert.equal(paymob.isCheckoutInProgress(stale, now), false);
  });
});
