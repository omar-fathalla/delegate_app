const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/subscription_logic");

// Noon Cairo on the 15th: safe instant for "a day in month m".
const mid = (y, m, d = 15) => new Date(Date.UTC(y, m - 1, d, 10));
const EXPECTED = [500, 416.67, 333.33, 250, 166.67, 83.33];

test("fee for every month of both halves (paid years)", () => {
  for (let m = 1; m <= 12; m++) {
    const at = mid(2027, m);
    assert.equal(L.remainingMonths(at), 6 - ((m - 1) % 6), `month ${m}`);
    assert.equal(L.feeAt(at), EXPECTED[(m - 1) % 6], `month ${m}`);
  }
  assert.deepEqual([1, 2, 3, 4, 5, 6].map(L.feeForMonths), [83.33, 166.67, 250, 333.33, 416.67, 500]);
});

test("join month counts in full: first and last day of a month cost the same", () => {
  assert.equal(L.feeAt(L.cairoMidnight(2027, 2, 1)), 416.67);
  assert.equal(L.feeAt(new Date(L.cairoMidnight(2027, 3, 1).getTime() - 1)), 416.67);
  assert.equal(L.feeAt(L.cairoMidnight(2027, 3, 1)), 333.33);
});

test("rounding is half-up to 2 decimals, in one helper", () => {
  assert.equal(L.roundMoney(416.666666), 416.67);
  assert.equal(L.roundMoney(83.333333), 83.33);
  assert.equal(L.roundMoney(1.005), 1.01);
  assert.equal(L.toCents(416.67), 41667);
  assert.equal(L.quoteFor(["a", "b", "c"], mid(2027, 2)).amount, 1250.01);
  assert.equal(L.quoteFor(["a", "b", "c"], mid(2027, 2)).amountCents, 125001);
});

test("max delegates per renewal constant", () => {
  assert.equal(L.MAX_DELEGATES_PER_RENEWAL, 100);
});

test("free promotion boundary: free through 2026-12-31 23:59:59 Cairo, paid from 2027-01-01 00:00 Cairo", () => {
  const jan1 = L.cairoMidnight(2027, 1, 1);
  assert.equal(jan1.toISOString(), "2026-12-31T22:00:00.000Z");
  assert.equal(L.isFreePromotion(new Date(jan1.getTime() - 1000)), true);
  assert.equal(L.feeAt(new Date(jan1.getTime() - 1000)), 0);
  assert.equal(L.isFreePromotion(jan1), false);
  assert.equal(L.feeAt(jan1), 500);
  // 23:30 UTC on 31 Dec is already 1 Jan in Cairo.
  assert.equal(L.feeAt(new Date("2026-12-31T23:30:00Z")), 500);
  for (let m = 1; m <= 12; m++) assert.equal(L.feeAt(mid(2026, m)), 0);
  assert.equal(L.periodOf(jan1).code, "2027_H1");
});

test("period boundaries in Cairo time, including summer time on 1 July", () => {
  const jul1 = L.cairoMidnight(2027, 7, 1);
  assert.equal(jul1.toISOString(), "2027-06-30T21:00:00.000Z"); // UTC+3 in summer
  assert.equal(L.periodOf(new Date(jul1.getTime() - 1)).code, "2027_H1");
  assert.equal(L.periodOf(jul1).code, "2027_H2");
  assert.equal(L.periodOf(new Date("2027-06-30T21:30:00Z")).code, "2027_H2");
  const h1 = L.periodFor(2027, 1);
  assert.equal(h1.startDay, "2027-01-01");
  assert.equal(h1.endDay, "2027-06-30");
  assert.equal(h1.endsAt.getTime(), jul1.getTime());
  const h2 = L.periodFor(2027, 2);
  assert.equal(h2.endDay, "2027-12-31");
  assert.equal(h2.endsAt.toISOString(), "2027-12-31T22:00:00.000Z");
  assert.equal(L.parsePeriodCode("2027_H2").code, "2027_H2");
  assert.equal(L.parsePeriodCode("2027-H2"), null);
});

test("app-added delegates come only from approved app new_delegate requests", () => {
  const ok = {requestType: "new_delegate", status: "approved", supervisorUid: "sup"};
  assert.equal(L.isAppAddedRegistration("d1", ok), true);
  assert.equal(L.isAppAddedRegistration("d1", {...ok, requestType: undefined}), true);
  assert.equal(L.isAppAddedRegistration("d1", {...ok, status: "pending"}), false);
  assert.equal(L.isAppAddedRegistration("d1", {...ok, supervisorUid: ""}), false); // web self-requests
  assert.equal(L.isAppAddedRegistration("d1", {...ok, requestType: "add_organization"}), false);
  assert.equal(L.isAppAddedRegistration("d1", {...ok, existingDelegateUid: "web1"}), false);
});

test("coverage: paid covers its period; waived only covers free periods; add_organization covers nobody", () => {
  assert.deepEqual(L.coveredUids("r1", {requestType: "new_delegate"}), ["r1"]);
  assert.deepEqual(L.coveredUids("r2", {requestType: "renewal", coveredDelegateUids: ["a", "b", "a", ""]}), ["a", "b"]);
  assert.deepEqual(L.coveredUids("r3", {requestType: "add_organization"}), []);
  assert.equal(L.requestCoversPeriod({periodCode: "2027_H1", paymentStatus: "paid"}, "2027_H1"), true);
  assert.equal(L.requestCoversPeriod({periodCode: "2027_H1", paymentStatus: "pending"}, "2027_H1"), false);
  assert.equal(L.requestCoversPeriod({periodCode: "2027_H1", paymentStatus: "failed"}, "2027_H1"), false);
  assert.equal(L.requestCoversPeriod({periodCode: "2026_H2", paymentStatus: "paid"}, "2027_H1"), false);
  assert.equal(L.requestCoversPeriod({periodCode: "2027_H1", paymentStatus: "waived"}, "2027_H1"), false);
  assert.equal(L.requestCoversPeriod({periodCode: "2026_H2", paymentStatus: "waived"}, "2026_H2"), true);
});

test("free-period bypass is honored only for tashil-dev and a listed company", () => {
  const at = mid(2026, 6);
  const dev = {projectId: "tashil-dev", companyUID: "co_dev_renewal_paid", bypassCompanyUIDs: ["co_dev_renewal_paid"]};
  const prod = {projectId: "practice-firebase-72df1", companyUID: "co_dev_renewal_paid", bypassCompanyUIDs: ["co_dev_renewal_paid"]};
  const flagOnProd = {projectId: "practice-firebase-72df1", companyUID: "co_dev_renewal_paid", companyFreePeriodEnded: true};
  const flagOnDev = {projectId: "tashil-dev", companyUID: "co_dev_renewal_paid", companyFreePeriodEnded: true};
  const otherCo = {projectId: "tashil-dev", companyUID: "co_other", bypassCompanyUIDs: ["co_dev_renewal_paid"]};
  const noCompany = {projectId: "tashil-dev", bypassCompanyUIDs: ["co_dev_renewal_paid"]};

  assert.equal(L.shouldBypassFreePeriod(dev), true);
  assert.equal(L.shouldBypassFreePeriod(flagOnDev), true);
  assert.equal(L.shouldBypassFreePeriod(prod), false);
  assert.equal(L.shouldBypassFreePeriod(flagOnProd), false);
  assert.equal(L.shouldBypassFreePeriod(otherCo), false);
  assert.equal(L.shouldBypassFreePeriod(noCompany), false);
  assert.equal(L.shouldBypassFreePeriod({}), false);

  assert.equal(L.isFreePromotion(at, dev), false);
  assert.equal(L.isFreePromotion(at, prod), true);
  assert.equal(L.isFreePromotion(at, flagOnProd), true);
  assert.equal(L.feeAt(at, dev), L.feeForMonths(L.remainingMonths(at)));
  assert.equal(L.feeAt(at, prod), 0);
  assert.equal(L.quoteFor(["a"], at, dev).amountCents > 0, true);
  assert.equal(L.quoteFor(["a"], at, prod).amountCents, 0);
});
