"use strict";

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
const TEST_INTEGRATION_ID = paymob.TASHIL_DEV_PAYMOB_INTEGRATION_ID;
const ALLOWED_INTEGRATIONS = [TEST_INTEGRATION_ID];
const AT = new Date("2027-02-10T10:00:00.000Z");
const FEE = 416.67;
const CENTS = 41667;
const REQUEST_ID = "ren1";
const ATTEMPT_NEW = "1700000000002_newabcd12";
const ATTEMPT_OLD = "1700000000001_oldabcd12";

function paymobEnv() {
  return {
    baseUrl: "https://accept.paymob.com",
    secretKey: "sk_test_placeholder",
    publicKey: "pk_test_placeholder",
    hmacSecret: SECRET,
    integrationIds: [TEST_INTEGRATION_ID],
  };
}

function intentionDuplicateRef() {
  return async () => ({
    ok: false,
    status: 400,
    text: async () => JSON.stringify({detail: "Order with ref already exists"}),
  });
}

function sampleObj(overrides = {}) {
  return {
    amount_cents: CENTS,
    created_at: "2027-02-10T10:00:00.000000",
    currency: "EGP",
    error_occured: false,
    has_parent_transaction: false,
    id: 1001,
    integration_id: TEST_INTEGRATION_ID,
    is_3d_secure: true,
    is_auth: false,
    is_capture: false,
    is_refunded: false,
    is_standalone_payment: true,
    is_voided: false,
    order: {id: 5001, merchant_order_id: REQUEST_ID},
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

function hookOpts(db, obj) {
  return {
    obj,
    hmac: sign(obj),
    hmacSecret: SECRET,
    integrationIds: ALLOWED_INTEGRATIONS,
    db,
    now: AT,
  };
}

async function seedPrivilegedStaff(db) {
  await db.doc("users/sa1").set({role: "super-admin", organizationUID: "org1"});
  await db.doc("users/ts1").set({role: "technical_support", organizationUID: "org1"});
  await db.doc("fcm_tokens/sa1").set({token: "fcm_sa1"});
  await db.doc("fcm_tokens/ts1").set({token: "fcm_ts1"});
}

async function seed(db, checkout = null) {
  await seedPrivilegedStaff(db);
  await db.doc("users/sup1").set({
    role: "supervisor",
    organizationUID: "org1",
    companyUID: "co1",
  });
  await db.collection("delegate_requests").doc("d1").set({
    requestType: "new_delegate",
    status: "approved",
    supervisorUid: "sup1",
    companyUID: "co1",
    organizationUID: "org1",
  });
  await db.doc("organizations/org1/companies/co1/delegates/d1").set({
    uid: "d1",
    fullName: "d1",
    status: "active",
  });
  const data = {
    requestType: "renewal",
    status: "pending",
    paymentStatus: "pending",
    companyUID: "co1",
    organizationUID: "org1",
    supervisorUid: "sup1",
    periodCode: "2027_H1",
    coveredDelegateUids: ["d1"],
    items: [{uid: "d1", fee: FEE, fullName: "d1"}],
    amountDue: FEE,
    fee: FEE,
    remainingMonths: 5,
    quotedAt: Timestamp.fromDate(AT),
    createdAt: Timestamp.fromDate(AT),
  };
  if (checkout) data.paymobCheckout = checkout;
  await db.collection("delegate_requests").doc(REQUEST_ID).set(data);
}

async function seedAttempt(db, attemptId, specialReference) {
  await db.collection("delegate_requests").doc(REQUEST_ID)
    .collection("paymob_checkout_attempts").doc(attemptId).set({
      attemptId,
      specialReference,
      createdAt: Timestamp.fromDate(AT),
    });
}

async function countPaymentEvents(db) {
  const snap = await db.collection("subscription_payment_events").get();
  return snap.size;
}

async function countSuperseded(db) {
  const snap = await db.collection("paymob_superseded_payments").get();
  return snap.size;
}

async function countNotifications(db) {
  const snap = await db.collection("notifications").get();
  return snap.size;
}

async function countAdminAlerts(db) {
  const snap = await db.collection("admin_alerts").get();
  return snap.size;
}

function mockMessaging() {
  const sends = [];
  return {
    sends,
    messaging: {
      send: async (msg) => {
        sends.push(msg);
        return "mock_msg_id";
      },
    },
  };
}

describe("paymob special_reference", () => {
  it("builds and resolves composite references with legacy fallback", () => {
    const attempt = "1700000000000_abc12";
    const ref = paymob.buildPaymobSpecialReference(REQUEST_ID, attempt);
    assert.equal(ref, `${REQUEST_ID}${paymob.PAYMOB_SPECIAL_REF_DELIMITER}${attempt}`);
    assert.equal(paymob.resolveRequestIdFromPaymobReference(ref), REQUEST_ID);
    assert.equal(paymob.attemptIdFromPaymobReference(ref), attempt);
    assert.equal(paymob.resolveRequestIdFromPaymobReference(REQUEST_ID), REQUEST_ID);
    assert.equal(paymob.attemptIdFromPaymobReference(REQUEST_ID), "");
  });

  it("splits on the last delimiter when requestId contains __", () => {
    const requestId = "req__with__parts";
    const attempt = "1700000000009_suffix01";
    const ref = paymob.buildPaymobSpecialReference(requestId, attempt);
    assert.equal(paymob.resolveRequestIdFromPaymobReference(ref), requestId);
    assert.equal(paymob.attemptIdFromPaymobReference(ref), attempt);
  });

  it("maps Paymob duplicate-reference errors to PaymobIntentionError", async () => {
    await assert.rejects(
      () => paymob.createPaymobIntention({
        env: paymobEnv(),
        amountCents: CENTS,
        specialReference: REQUEST_ID,
        notificationUrl: "https://example.com/hook",
        billing: {
          first_name: "A",
          last_name: "B",
          email: "a@b.test",
          phone_number: "01000000000",
        },
        itemName: "renewal",
        itemCount: 1,
        fetchImpl: intentionDuplicateRef(),
      }),
      (e) => e instanceof paymob.PaymobIntentionError && e.reason === "paymob_duplicate_reference",
    );
  });

  it("(a) pending then retry uses a new special_reference and both intentions succeed", async () => {
    const refs = [];
    let call = 0;
    const fetchImpl = async () => {
      call += 1;
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({
          id: `pi_${call}`,
          client_secret: `csk_${call}`,
        }),
      };
    };
    const base = {
      env: paymobEnv(),
      amountCents: CENTS,
      notificationUrl: "https://example.com/hook",
      billing: {
        first_name: "A",
        last_name: "B",
        email: "a@b.test",
        phone_number: "01000000000",
      },
      itemName: "renewal",
      itemCount: 1,
      fetchImpl: async (url, init) => {
        const body = JSON.parse(init.body);
        refs.push(body.special_reference);
        return fetchImpl();
      },
    };
    const attemptA = "1700000000003_aaaa1111";
    const attemptB = "1700000000004_bbbb2222";
    await paymob.createPaymobIntention({
      ...base,
      specialReference: paymob.buildPaymobSpecialReference(REQUEST_ID, attemptA),
    });
    await paymob.createPaymobIntention({
      ...base,
      specialReference: paymob.buildPaymobSpecialReference(REQUEST_ID, attemptB),
    });
    assert.equal(refs.length, 2);
    assert.notEqual(refs[0], refs[1]);
  });

  it("rejects webhooks when integration_id is not configured", async () => {
    const db = new MemoryFirestore();
    const obj = sampleObj({integration_id: 999999});
    const result = await paymob.handlePaymobWebhook(hookOpts(db, obj));
    assert.equal(result.outcome, "rejected_integration");
    assert.equal(await countPaymentEvents(db), 0);
  });

  describe("(b) two attempts and late webhook", () => {
    let db;
    beforeEach(async () => {
      db = new MemoryFirestore();
      await seed(db, {
        attemptId: ATTEMPT_NEW,
        specialReference: paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_NEW),
        createdAt: Timestamp.fromDate(AT),
      });
      await seedAttempt(db, ATTEMPT_NEW,
        paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_NEW));
      await seedAttempt(db, ATTEMPT_OLD,
        paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_OLD));
      await jobs.quoteSubscriptionRequest(db, REQUEST_ID, AT);
    });

    it("ignores a late failed webhook from a superseded attempt", async () => {
      const oldRef = paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_OLD);
      const obj = sampleObj({
        success: false,
        id: 9001,
        order: {id: 5002, merchant_order_id: oldRef},
      });
      const result = await paymob.handlePaymobWebhook(hookOpts(db, obj));
      assert.equal(result.outcome, "ignored_stale_attempt");
      assert.equal(await countPaymentEvents(db), 0);
    });

    it("records superseded success without extra payment events", async () => {
      const paidRef = paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_NEW);
      const paidObj = sampleObj({
        success: true,
        id: 82002,
        order: {id: 5003, merchant_order_id: paidRef},
      });
      assert.equal((await paymob.handlePaymobWebhook(hookOpts(db, paidObj))).outcome, "paid");
      assert.equal(await countPaymentEvents(db), 1);
      const oldRef = paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_OLD);
      const lateObj = sampleObj({
        success: true,
        id: 82001,
        order: {id: 5004, merchant_order_id: oldRef},
      });
      const {sends, messaging} = mockMessaging();
      const late = await paymob.handlePaymobWebhook({...hookOpts(db, lateObj), messaging});
      assert.equal(late.outcome, "superseded_needs_refund");
      assert.equal(await countPaymentEvents(db), 1);
      assert.equal(await countSuperseded(db), 1);
      assert.equal(await countAdminAlerts(db), 1);
      assert.equal(await countNotifications(db), 2);
      assert.equal(sends.length, 2);
      assert.equal(sends[0].data.paymobTransactionId, "82001");
      const superseded = (await db.collection("paymob_superseded_payments").doc("82001").get()).data();
      assert.equal(superseded.needs_refund, true);
      assert.equal(superseded.requestId, REQUEST_ID);
      assert.equal(superseded.attemptId, ATTEMPT_OLD);
      assert.equal(superseded.paymobTransactionId, "82001");
      const alert = (await db.collection("admin_alerts").doc("82001").get()).data();
      assert.equal(alert.needs_refund, true);
      assert.equal(alert.type, "paymob_superseded_payment");
    });
  });

  it("rejects unknown foreign attempts with no payment event", async () => {
    const db = new MemoryFirestore();
    await seed(db, {
      attemptId: ATTEMPT_NEW,
      specialReference: paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_NEW),
    });
    await seedAttempt(db, ATTEMPT_NEW,
      paymob.buildPaymobSpecialReference(REQUEST_ID, ATTEMPT_NEW));
    await jobs.quoteSubscriptionRequest(db, REQUEST_ID, AT);
    const foreign = "1700000000999_forge8888";
    const ref = paymob.buildPaymobSpecialReference(REQUEST_ID, foreign);
    const obj = sampleObj({
      success: true,
      id: 88001,
      order: {id: 5099, merchant_order_id: ref},
    });
    const result = await paymob.handlePaymobWebhook(hookOpts(db, obj));
    assert.equal(result.outcome, "rejected_foreign_attempt");
    assert.equal(await countPaymentEvents(db), 0);
    assert.equal(await countSuperseded(db), 0);
  });

  it("(c) legacy bare requestId in webhook still resolves the request", async () => {
    const db = new MemoryFirestore();
    await seed(db);
    await jobs.quoteSubscriptionRequest(db, REQUEST_ID, AT);
    const obj = sampleObj({
      success: true,
      id: 7007,
      order: {id: 5010, merchant_order_id: REQUEST_ID},
    });
    const result = await paymob.handlePaymobWebhook(hookOpts(db, obj));
    assert.equal(paymob.requestIdFromPaymobObj(obj), REQUEST_ID);
    assert.equal(result.outcome, "paid");
  });
});