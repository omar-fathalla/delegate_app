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

test("renewal coverage expires at end of Cairo quote month, or period end if earlier", () => {
  const feb = mid(2027, 2);
  const mar1 = L.cairoMidnight(2027, 3, 1);
  assert.equal(L.endOfCairoMonth(feb).getTime(), mar1.getTime());
  assert.equal(L.renewalCoverageExpiryAt(feb, "2027_H1").getTime(), mar1.getTime());
  assert.equal(L.isRenewalCoverageExpired(feb, new Date(mar1.getTime() - 1), "2027_H1"), false);
  assert.equal(L.isRenewalCoverageExpired(feb, mar1, "2027_H1"), true);

  // 15 June: end of month and H1 period end are the same instant (1 Jul Cairo).
  const jun = mid(2027, 6);
  const jul1 = L.cairoMidnight(2027, 7, 1);
  assert.equal(L.endOfCairoMonth(jun).getTime(), jul1.getTime());
  assert.equal(L.renewalCoverageExpiryAt(jun, "2027_H1").getTime(), jul1.getTime());
  assert.equal(L.periodFor(2027, 1).endsAt.getTime(), jul1.getTime());
  assert.equal(L.isRenewalCoverageExpired(jun, jul1, "2027_H1"), true);

  // Mid-December H2: expiry is 1 Jan of the next year (period end).
  const dec = mid(2027, 12);
  const jan1 = L.cairoMidnight(2028, 1, 1);
  assert.equal(L.renewalCoverageExpiryAt(dec, "2027_H2").getTime(), jan1.getTime());
});

test("advance renewal window and next-period quote", () => {
  const cfgOff = L.parseAdvanceRenewalConfig(null);
  assert.equal(cfgOff.enabled, false);
  assert.equal(cfgOff.days, L.DEFAULT_ADVANCE_RENEWAL_DAYS);

  const cfg = L.parseAdvanceRenewalConfig({advanceRenewalEnabled: true, advanceRenewalDays: 30});
  assert.equal(cfg.enabled, true);
  assert.equal(cfg.days, 30);
  assert.equal(L.parseAdvanceRenewalConfig({advanceRenewalEnabled: true, advanceRenewalDays: 0}).days, L.DEFAULT_ADVANCE_RENEWAL_DAYS);

  const h2 = L.periodOf(L.cairoMidnight(2026, 11, 11));
  assert.equal(h2.code, "2026_H2");
  assert.equal(L.nextPeriod(h2).code, "2027_H1");
  assert.equal(L.nextPeriod(L.periodFor(2027, 1)).code, "2027_H2");

  const opens30 = L.advanceWindowOpensAt(h2, 30);
  assert.equal(opens30.getTime(), L.cairoMidnight(2026, 12, 2).getTime());
  const opens60 = L.advanceWindowOpensAt(h2, 60);
  assert.equal(opens60.getTime(), L.cairoMidnight(2026, 11, 2).getTime());

  const dec15 = L.cairoMidnight(2026, 12, 15);
  const nov11 = L.cairoMidnight(2026, 11, 11);
  const jan1 = L.cairoMidnight(2027, 1, 1);
  assert.equal(L.isAdvanceRenewalOpen(dec15, cfg, h2), true);
  assert.equal(L.isAdvanceRenewalOpen(nov11, cfg, h2), false);
  assert.equal(L.isAdvanceRenewalOpen(nov11, {enabled: true, days: 60}, h2), true);
  assert.equal(L.isAdvanceRenewalOpen(dec15, cfgOff, h2), false);
  assert.equal(L.isAdvanceRenewalOpen(jan1, cfg), false);

  assert.equal(L.resolvePayablePeriod(dec15, "2026_H2", cfg).code, "2026_H2");
  assert.equal(L.resolvePayablePeriod(dec15, "2027_H1", cfg).code, "2027_H1");
  assert.equal(L.resolvePayablePeriod(dec15, "2027_H1", cfgOff), null);
  assert.equal(L.resolvePayablePeriod(nov11, "2027_H1", cfg), null);
  assert.equal(L.resolvePayablePeriod(dec15, "2027_H2", cfg), null);

  const advanceQuote = L.quoteFor(["a"], dec15, {periodCode: "2027_H1"});
  assert.equal(advanceQuote.periodCode, "2027_H1");
  assert.equal(advanceQuote.amount, 500);
  assert.equal(advanceQuote.amountCents, 50000);
  assert.equal(advanceQuote.remainingMonths, 6);

  const currentInPromo = L.quoteFor(["a"], dec15);
  assert.equal(currentInPromo.periodCode, "2026_H2");
  assert.equal(currentInPromo.amount, 0);
});

test("parseFreePromotionLastDay reads config or falls back", () => {
  assert.equal(L.parseFreePromotionLastDay(null), "2026-12-31");
  assert.equal(L.parseFreePromotionLastDay({}), "2026-12-31");
  assert.equal(L.parseFreePromotionLastDay({freePromotionLastDay: "2026-11-30"}), "2026-11-30");
  assert.equal(L.parseFreePromotionLastDay({freePromotionLastDay: "bad"}), "2026-12-31");
});

test("isFreePromotion honors the configured last day and the Cairo midnight boundary", () => {
  const justBefore = new Date("2026-12-31T21:59:59.000Z");
  const exactlyMidnightCairo = new Date("2026-12-31T22:00:00.000Z");
  assert.equal(L.isFreePromotion(justBefore), true);
  assert.equal(L.isFreePromotion(exactlyMidnightCairo), false);
  assert.equal(L.isFreePromotion(new Date("2026-12-01T00:00:00.000Z"), {freePromotionLastDay: "2026-11-30"}), false);
  assert.equal(L.isFreePromotion(new Date("2026-11-30T21:59:59.000Z"), {freePromotionLastDay: "2026-11-30"}), true);
});

test("two delegates at 2 months total 333.34 (same as the Dart helper)", () => {
  assert.equal(L.feeForMonths(2), 166.67);
  assert.equal(L.roundMoney(L.feeForMonths(2) * 2), 333.34);
  assert.equal(L.toCents(333.34), 33334);
});

test("expires an awaiting request after the 60-minute checkout TTL", () => {
  const quotedAt = new Date("2027-02-10T10:00:00.000Z");
  const data = {paymentStatus: "pending", quotedAt, periodCode: "2027_H1"};
  assert.equal(L.isAwaitingPaymentExpired(data, new Date("2027-02-10T10:59:00.000Z")), false);
  assert.equal(L.isAwaitingPaymentExpired(data, new Date("2027-02-10T11:00:00.000Z")), true);
  const withCheckout = {
    paymentStatus: "pending",
    quotedAt,
    periodCode: "2027_H1",
    paymobCheckout: {createdAt: new Date("2027-02-10T10:30:00.000Z")},
  };
  // TTL is measured from checkout start when present.
  assert.equal(L.isAwaitingPaymentExpired(withCheckout, new Date("2027-02-10T11:20:00.000Z")), false);
  assert.equal(L.isAwaitingPaymentExpired(withCheckout, new Date("2027-02-10T11:30:00.000Z")), true);
});

test("subscription grace blocks suspension 1–14 Jan and 1–14 Jul (Cairo)", () => {
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 1, 1)), true);
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 1, 14)), true);
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 1, 15)), false);
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 7, 1)), true);
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 7, 14)), true);
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 7, 15)), false);
  assert.equal(L.isWithinSubscriptionGrace(L.cairoMidnight(2027, 3, 1)), false);
});

test("subscription reminder day is 14 Cairo days before period end", () => {
  const h1 = L.periodFor(2027, 1);
  assert.equal(L.subscriptionReminderCairoDay(h1, 14), "2027-06-16");
  const h2 = L.periodFor(2027, 2);
  assert.equal(L.subscriptionReminderCairoDay(h2, 14), "2027-12-17");
  const jun16 = L.cairoMidnight(2027, 6, 16);
  assert.equal(L.isSubscriptionReminderDay(jun16, 14), true);
  assert.equal(L.isSubscriptionReminderDay(L.cairoMidnight(2027, 6, 15), 14), false);
  assert.equal(L.parseSubscriptionReminderDays({subscriptionReminderDays: 7}), 7);
  assert.equal(L.parseSubscriptionReminderDays({subscriptionReminderDays: 0}), L.DEFAULT_SUBSCRIPTION_REMINDER_DAYS);
});

test("does not expire a paid request even after the checkout TTL", () => {
  const data = {
    paymentStatus: "paid",
    quotedAt: new Date("2027-02-01T00:00:00.000Z"),
    periodCode: "2027_H1",
  };
  assert.equal(L.isAwaitingPaymentExpired(data, new Date("2027-02-10T12:00:00.000Z")), false);
});
