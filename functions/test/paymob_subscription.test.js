const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");
const path = require("path");

const hmac = require(path.join(__dirname, "../lib/paymob_hmac.js"));
const paymob = require(path.join(__dirname, "../lib/paymob_subscription.js"));

const SECRET = "test-hmac-secret";

function sampleObj(overrides = {}) {
  return {
    amount_cents: 41667,
    created_at: "2026-11-11T21:00:00.000000",
    currency: "EGP",
    error_occured: false,
    has_parent_transaction: false,
    id: 192036465,
    integration_id: 4097558,
    is_3d_secure: true,
    is_auth: false,
    is_capture: false,
    is_refunded: false,
    is_standalone_payment: true,
    is_voided: false,
    order: {id: 217503754, merchant_order_id: "req1"},
    owner: 302852,
    pending: false,
    source_data: {pan: "2346", sub_type: "MasterCard", type: "card"},
    success: true,
    ...overrides,
  };
}

function sign(obj, secret = SECRET) {
  return crypto.createHmac("sha512", secret)
    .update(hmac.transactionPostHmacPayload(obj))
    .digest("hex");
}

describe("paymob hmac", () => {
  it("accepts a matching SHA-512 HMAC and rejects a tampered amount", () => {
    const obj = sampleObj();
    const good = sign(obj);
    assert.equal(hmac.verifyTransactionPostHmac(obj, good, SECRET), true);
    assert.equal(hmac.verifyTransactionPostHmac(obj, good.toUpperCase(), SECRET), true);
    const bad = sampleObj({amount_cents: 1});
    assert.equal(hmac.verifyTransactionPostHmac(bad, good, SECRET), false);
    assert.equal(hmac.verifyTransactionPostHmac(obj, "00", SECRET), false);
    assert.equal(hmac.verifyTransactionPostHmac(obj, good, ""), false);
  });

  it("uses the documented 20-field concatenation order", () => {
    const obj = sampleObj();
    const expected = [
      41667, "2026-11-11T21:00:00.000000", "EGP", false, false, 192036465,
      4097558, true, false, false, false, true, false, 217503754, 302852,
      false, "2346", "MasterCard", "card", true,
    ].map(String).join("");
    assert.equal(hmac.transactionPostHmacPayload(obj), expected);
    assert.equal(hmac.TRANSACTION_POST_HMAC_FIELDS.length, 20);
  });
});

describe("paymob env", () => {
  const base = {
    PAYMOB_SECRET_KEY: "sk_test_abc",
    PAYMOB_PUBLIC_KEY: "pk_test_def",
    PAYMOB_HMAC_SECRET: "hmac",
    PAYMOB_INTEGRATION_ID_CARD: "12345",
  };
  it("accepts test keys and refuses live keys", () => {
    const ok = paymob.readPaymobEnv(base);
    assert.equal("error" in ok, false);
    assert.deepEqual(ok.integrationIds, [12345]);
    assert.equal(paymob.readPaymobEnv({...base, PAYMOB_SECRET_KEY: "sk_live_abc"}).error, "paymob_live_forbidden");
    assert.equal(paymob.readPaymobEnv({...base, PAYMOB_PUBLIC_KEY: "pk_live_def"}).error, "paymob_live_forbidden");
    assert.equal(paymob.readPaymobEnv({...base, PAYMOB_LIVE: "true"}).error, "paymob_live_forbidden");
    assert.equal(paymob.readPaymobEnv({}).error, "paymob_not_configured");
  });

  it("accepts regional and classic test keys and refuses live keys", () => {
    const regional = paymob.readPaymobEnv({
      ...base,
      PAYMOB_SECRET_KEY: "egy_sk_test_PLACEHOLDER",
      PAYMOB_PUBLIC_KEY: "egy_pk_test_PLACEHOLDER",
    });
    assert.equal("error" in regional, false);
    assert.equal(regional.secretKey, "egy_sk_test_PLACEHOLDER");
    assert.equal(regional.publicKey, "egy_pk_test_PLACEHOLDER");

    const classic = paymob.readPaymobEnv({
      ...base,
      PAYMOB_SECRET_KEY: "sk_test_PLACEHOLDER",
      PAYMOB_PUBLIC_KEY: "pk_test_PLACEHOLDER",
    });
    assert.equal("error" in classic, false);

    const mixed = paymob.readPaymobEnv({
      ...base,
      PAYMOB_SECRET_KEY: "egy_sk_test_PLACEHOLDER",
      PAYMOB_PUBLIC_KEY: "pk_test_PLACEHOLDER",
    });
    assert.equal("error" in mixed, false);

    for (const region of ["om", "egypt"]) {
      const bounded = paymob.readPaymobEnv({
        ...base,
        PAYMOB_SECRET_KEY: `${region}_sk_test_PLACEHOLDER`,
        PAYMOB_PUBLIC_KEY: `${region}_pk_test_PLACEHOLDER`,
      });
      assert.equal("error" in bounded, false);
    }

    for (const secretKey of ["egy_sk_live_PLACEHOLDER", "sk_live_PLACEHOLDER"]) {
      assert.equal(
        paymob.readPaymobEnv({...base, PAYMOB_SECRET_KEY: secretKey}).error,
        "paymob_live_forbidden",
      );
    }
    for (const publicKey of ["egy_pk_live_PLACEHOLDER", "pk_live_PLACEHOLDER"]) {
      assert.equal(
        paymob.readPaymobEnv({...base, PAYMOB_PUBLIC_KEY: publicKey}).error,
        "paymob_live_forbidden",
      );
    }
    assert.equal(
      paymob.readPaymobEnv({
        ...base,
        PAYMOB_SECRET_KEY: "egy_sk_test_PLACEHOLDER",
        PAYMOB_PUBLIC_KEY: "egy_pk_test_PLACEHOLDER",
        PAYMOB_LIVE: "true",
      }).error,
      "paymob_live_forbidden",
    );
    assert.equal(
      paymob.readPaymobEnv({
        ...base,
        PAYMOB_SECRET_KEY: "egy_sk_test_PLACEHOLDER",
        PAYMOB_PUBLIC_KEY: "egy_pk_test_PLACEHOLDER",
        PAYMOB_MODE: "live",
      }).error,
      "paymob_live_forbidden",
    );
    assert.equal(
      paymob.readPaymobEnv({...base, PAYMOB_SECRET_KEY: "e_sk_test_PLACEHOLDER"}).error,
      "paymob_test_keys_required",
    );
    assert.equal(
      paymob.readPaymobEnv({...base, PAYMOB_PUBLIC_KEY: "abcdef_pk_test_PLACEHOLDER"}).error,
      "paymob_test_keys_required",
    );
    assert.equal(
      paymob.readPaymobEnv({...base, PAYMOB_SECRET_KEY: "EGY_sk_test_PLACEHOLDER"}).error,
      "paymob_test_keys_required",
    );
    assert.equal(
      paymob.readPaymobEnv({...base, PAYMOB_SECRET_KEY: "xx_extra_sk_live_PLACEHOLDER"}).error,
      "paymob_live_forbidden",
    );
  });

  it("builds the unified checkout URL", () => {
    const url = paymob.checkoutUrl("https://accept.paymob.com", "pk_test_x", "egy_csk_test_y");
    assert.equal(
      url,
      "https://accept.paymob.com/unifiedcheckout/?publicKey=pk_test_x&clientSecret=egy_csk_test_y",
    );
  });

  it("reads requestId from merchant_order_id", () => {
    assert.equal(paymob.requestIdFromPaymobObj(sampleObj()), "req1");
  });
});

describe("paymob webhook handler", () => {
  it("returns 401 and does not apply on a bad HMAC", async () => {
    const applied = [];
    const fakeDb = {};
    // handlePaymobWebhook calls applyVerified only after HMAC. Stub by
    // using an isolated path: bad hmac never needs db.
    const result = await paymob.handlePaymobWebhook({
      obj: sampleObj(),
      hmac: "deadbeef",
      hmacSecret: SECRET,
      db: fakeDb,
    });
    assert.equal(result.status, 401);
    assert.equal(result.outcome, "invalid_hmac");
    assert.equal(applied.length, 0);
  });

  it("ignores a verified pending callback", async () => {
    const obj = sampleObj({pending: true, success: false});
    const result = await paymob.handlePaymobWebhook({
      obj,
      hmac: sign(obj),
      hmacSecret: SECRET,
      db: {},
    });
    assert.equal(result.status, 200);
    assert.equal(result.outcome, "ignored_pending");
  });
});
