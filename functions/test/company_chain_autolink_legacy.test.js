// Legacy (app 1.14.x) subscription maps must count as coverage, like the
// new Paymob shape. Mirrors test/core/utils/subscription_coverage_legacy_test.dart.
const test = require("node:test");
const assert = require("node:assert/strict");
const {mapCoversPeriod, isCovered, legacyEndDatePassed} = require("../lib/company_chain_autolink_logic");

const legacy = (o = {}) => ({
  startDate: "2026-07-01T00:00:00.000",
  cycle: "2026_H2",
  isPaid: true,
  paymentMethod: "freePromotion",
  endDate: "2026-12-31T23:59:59.000",
  approvedAt: "2026-11-01T19:05:32.441777",
  approvedBy: "Omar Fathalla",
  ...o,
});
const promoNow = new Date("2026-11-18T10:00:00Z"); // 12:00 Cairo
const H2 = "2026_H2";

test("legacy freePromotion covers only while free", () => {
  assert.equal(mapCoversPeriod(legacy(), H2, true, promoNow), true);
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "free_promotion"}), H2, true, promoNow), true);
  assert.equal(mapCoversPeriod(legacy({isPaid: false}), H2, true, promoNow), true);
  assert.equal(mapCoversPeriod(legacy(), H2, false, promoNow), false);
});

test("legacy isPaid (branchReceipt / companyDeduction) covers, unpaid does not", () => {
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "branchReceipt"}), H2, false, promoNow), true);
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "companyDeduction"}), H2, false), true);
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "branchReceipt", isPaid: false}), H2, true), false);
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "branchReceipt", isPaid: "true"}), H2, true), false);
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "branchReceipt", isPaid: undefined}), H2, true), false);
});

test("wrong cycle / missing map / status only are not covered", () => {
  assert.equal(mapCoversPeriod(legacy({paymentMethod: "branchReceipt"}), "2027_H1", false), false);
  assert.equal(mapCoversPeriod(null, H2, true), false);
  assert.equal(mapCoversPeriod(undefined, H2, true), false);
  assert.equal(mapCoversPeriod({}, H2, true), false);
  assert.equal(mapCoversPeriod({status: "active"}, H2, true), false);
});

test("expired legacy endDate is not covered (Cairo wall time)", () => {
  const m = legacy({paymentMethod: "branchReceipt", endDate: "2026-11-17T23:59:59.000"});
  assert.equal(mapCoversPeriod(m, H2, false, promoNow), false);
  assert.equal(mapCoversPeriod(m, H2, false), true); // no instant -> no endDate check
  assert.equal(legacyEndDatePassed("2026-12-31T23:59:59.000", new Date("2026-12-31T21:58:00Z")), false);
  assert.equal(legacyEndDatePassed("2026-12-31T23:59:59.000", new Date("2026-12-31T22:01:00Z")), true);
  assert.equal(legacyEndDatePassed("2026-11-17T21:59:59Z", promoNow), true);
  assert.equal(legacyEndDatePassed({toDate: () => new Date("2026-11-17T00:00:00Z")}, promoNow), true);
  assert.equal(legacyEndDatePassed("garbage", promoNow), false);
  assert.equal(legacyEndDatePassed(undefined, promoNow), false);
});

test("new shape unchanged", () => {
  assert.equal(mapCoversPeriod({paymentStatus: "paid", periodCode: "2027_H1"}, "2027_H1", false), true);
  assert.equal(mapCoversPeriod({paymentStatus: "paid", periodCode: "2026_H2"}, "2027_H1", false), false);
  assert.equal(mapCoversPeriod({paymentStatus: "waived", periodCode: H2}, H2, true), true);
  assert.equal(mapCoversPeriod({paymentStatus: "waived", periodCode: H2}, H2, false), false);
  assert.equal(mapCoversPeriod({paymentStatus: "pending", periodCode: H2, isPaid: true}, H2, true), false);
  assert.equal(mapCoversPeriod({paymentStatus: "paid"}, H2, true), false);
});

test("isCovered uses legacy maps after the promotion (grace + next)", () => {
  const base = {
    free: false, periodCode: "2027_H1", covered: new Set(), inGrace: true,
    previousPeriodCode: H2, previousCovered: new Set(), freeChains: new Set(),
    now: new Date("2027-01-05T10:00:00Z"),
  };
  const paidCopy = [{orgId: "o1", data: {subscription: legacy({paymentMethod: "branchReceipt"})}}];
  const promoCopy = [{orgId: "o1", data: {subscription: legacy()}}];
  assert.equal(isCovered("u", paidCopy, base), true); // grace, endDate not applied
  assert.equal(isCovered("u", paidCopy, {...base, inGrace: false}), false);
  assert.equal(isCovered("u", promoCopy, base), false); // free promotion over
  const next = [{orgId: "o1", data: {nextSubscription: legacy({cycle: "2027_H1", paymentMethod: "branchReceipt", endDate: "2027-06-30T23:59:59.000"})}}];
  assert.equal(isCovered("u", next, {...base, inGrace: false}), true);
  assert.equal(isCovered("u", [], {...base, free: true}), true);
});
