"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const H = require("../lib/holds");
const S = require("../lib/subscription_holds");

const at = "2027-01-01T00:05:00.000Z";

test("M1 shadow add writes the expiry hold and leaves status fields out", () => {
  const r = S.planExpiryHoldWrite({
    data: {status: "active", uid: "app1"},
    op: "add", at, actor: "system", source: S.M1_SOURCE,
    periodCode: "2027_H1", mode: H.HOLDS_MODE_SHADOW,
  });
  assert.equal(r.ok, true);
  assert.equal(r.unchanged, false);
  assert.ok(r.update.holds[H.HOLD_SUBSCRIPTION_EXPIRED]);
  assert.equal(r.update.holds[H.HOLD_SUBSCRIPTION_EXPIRED].periodCode, "2027_H1");
  assert.equal(r.update.holds[H.HOLD_SUBSCRIPTION_EXPIRED].source, S.M1_SOURCE);
  assert.equal("status" in r.update, false);
  assert.equal("statusReason" in r.update, false);
  assert.equal(r.plan.derivedStatus, "suspended");
  assert.equal(r.plan.history.mode, H.HOLDS_MODE_SHADOW);
});

test("M1 authoritative add writes derived status and reason", () => {
  const r = S.planExpiryHoldWrite({
    data: {status: "approved", uid: "app3"},
    op: "add", at, actor: "system", source: S.M1_SOURCE,
    periodCode: "2027_H1", mode: H.HOLDS_MODE_AUTHORITATIVE,
  });
  assert.equal(r.ok, true);
  assert.equal(r.update.status, "suspended");
  assert.equal(r.update.statusReason, "subscription_expired");
});

test("M1 is idempotent when the expiry hold is already present", () => {
  const r = S.planExpiryHoldWrite({
    data: {status: "active", holds: {[H.HOLD_SUBSCRIPTION_EXPIRED]: {at, by: "system"}}},
    op: "add", at, actor: "system", source: S.M1_SOURCE,
    periodCode: "2027_H1", mode: H.HOLDS_MODE_SHADOW,
  });
  assert.equal(r.ok, true);
  assert.equal(r.unchanged, true);
  assert.deepEqual(r.update, {});
});

test("M1 stacks expiry on a manual / admin suspension without dropping that hold", () => {
  const r = S.planExpiryHoldWrite({
    data: {
      status: "suspended",
      statusReason: "manual",
      holds: {[H.HOLD_ADMIN_SUSPEND]: {at, by: "oa", note: "manual"}},
    },
    op: "add", at, actor: "system", source: S.M1_SOURCE,
    periodCode: "2027_H1", mode: H.HOLDS_MODE_AUTHORITATIVE,
  });
  assert.equal(r.ok, true);
  assert.equal(r.unchanged, false);
  assert.ok(r.update.holds[H.HOLD_ADMIN_SUSPEND]);
  assert.ok(r.update.holds[H.HOLD_SUBSCRIPTION_EXPIRED]);
  assert.equal(r.update.status, "suspended");
  assert.equal(r.update.statusReason, "admin_suspend");
});

test("M1 skips pending and rejected docs", () => {
  for (const status of ["pending", "rejected"]) {
    const r = S.planExpiryHoldWrite({
      data: {status},
      op: "add", at, actor: "system", source: S.M1_SOURCE,
      periodCode: "2027_H1", mode: H.HOLDS_MODE_SHADOW,
    });
    assert.equal(r.ok, false, status);
    assert.equal(r.reason, "status_not_actionable");
  }
});

test("M2 shadow remove clears the expiry hold and leaves status fields out", () => {
  const r = S.planExpiryHoldWrite({
    data: {
      status: "active",
      holds: {[H.HOLD_SUBSCRIPTION_EXPIRED]: {at, by: "system", periodCode: "2027_H1"}},
    },
    op: "remove", at, actor: "paymob", source: S.M2_SOURCE,
    requestId: "ren1", periodCode: "2027_H1", mode: H.HOLDS_MODE_SHADOW,
  });
  assert.equal(r.ok, true);
  assert.equal(r.unchanged, false);
  assert.equal(r.update.holds[H.HOLD_SUBSCRIPTION_EXPIRED], undefined);
  assert.equal("status" in r.update, false);
  assert.equal("statusReason" in r.update, false);
  assert.equal(r.plan.derivedStatus, "active");
});

test("M2 paid renewal does not remove an admin_suspend hold", () => {
  const r = S.planExpiryHoldWrite({
    data: {
      status: "suspended",
      holds: {
        [H.HOLD_SUBSCRIPTION_EXPIRED]: {at, by: "system"},
        [H.HOLD_ADMIN_SUSPEND]: {at, by: "oa"},
      },
    },
    op: "remove", at, actor: "paymob", source: S.M2_SOURCE,
    requestId: "ren1", mode: H.HOLDS_MODE_AUTHORITATIVE,
  });
  assert.equal(r.ok, true);
  assert.equal(r.update.holds[H.HOLD_ADMIN_SUSPEND].by, "oa");
  assert.equal(r.update.holds[H.HOLD_SUBSCRIPTION_EXPIRED], undefined);
  assert.equal(r.update.status, "suspended");
  assert.equal(r.update.statusReason, "admin_suspend");
});

test("M2 authoritative remove with only expiry sets status active", () => {
  const r = S.planExpiryHoldWrite({
    data: {
      status: "suspended",
      statusReason: "subscription_expired",
      holds: {[H.HOLD_SUBSCRIPTION_EXPIRED]: {at, by: "system"}},
    },
    op: "remove", at, actor: "paymob", source: S.M2_SOURCE,
    mode: H.HOLDS_MODE_AUTHORITATIVE,
  });
  assert.equal(r.ok, true);
  assert.equal(r.update.status, "active");
  assert.equal(r.update.statusReason, null);
});

test("M2 infers a legacy statusReason expiry hold when holds is missing", () => {
  const r = S.planExpiryHoldWrite({
    data: {status: "suspended", statusReason: "subscription_expired"},
    op: "remove", at, actor: "paymob", source: S.M2_SOURCE,
    inferLegacyExpiry: true, mode: H.HOLDS_MODE_SHADOW,
  });
  assert.equal(r.ok, true);
  assert.equal(r.inferredLegacy, true);
  assert.equal(r.unchanged, false);
  assert.deepEqual(r.update.holds, {});
  assert.equal("status" in r.update, false);
});

test("M2 without a hold or legacy reason is unchanged", () => {
  const r = S.planExpiryHoldWrite({
    data: {status: "active"},
    op: "remove", at, actor: "paymob", source: S.M2_SOURCE,
    inferLegacyExpiry: true, mode: H.HOLDS_MODE_SHADOW,
  });
  assert.equal(r.ok, true);
  assert.equal(r.unchanged, true);
});
