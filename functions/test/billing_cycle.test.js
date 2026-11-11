"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const B = require("../lib/billing_cycle");
const {periodOf} = require("../lib/subscription_logic");

const orgAdmin = {
  uid: "oa1",
  role: "organization_admin",
  organizationUID: "o1",
  companyUID: "c1",
};
const superAdmin = {uid: "sa", role: "super_admin", organizationUID: "", companyUID: ""};
const companyAdmin = {
  uid: "ca1",
  role: "company_admin",
  organizationUID: "o1",
  companyUID: "c1",
};

test("decideStartBillingCycle allows org admins of that org and super admins", () => {
  assert.equal(B.decideStartBillingCycle(orgAdmin, "o1", "2027_H1").ok, true);
  assert.equal(B.decideStartBillingCycle(superAdmin, "o1", "2027_H1").ok, true);
  assert.equal(B.decideStartBillingCycle({...orgAdmin, role: "organizationAdmin"}, "o1", "2027_H1").ok, true);
});

test("decideStartBillingCycle refuses company admins, other orgs, and empty org", () => {
  assert.equal(B.decideStartBillingCycle(companyAdmin, "o1", "2027_H1").reason, "caller_not_allowed");
  assert.equal(B.decideStartBillingCycle({...orgAdmin, organizationUID: "o2"}, "o1", "2027_H1").reason, "out_of_scope");
  assert.equal(B.decideStartBillingCycle({...orgAdmin, organizationUID: ""}, "o1", "2027_H1").reason, "out_of_scope");
  assert.equal(B.decideStartBillingCycle({...orgAdmin, isActive: false}, "o1", "2027_H1").reason, "caller_inactive");
  assert.equal(B.decideStartBillingCycle({uid: "x", role: "delegate", organizationUID: "o1"}, "o1", "2027_H1").reason, "caller_not_allowed");
});

test("decideStartBillingCycle rejects a bad org or cycle id", () => {
  assert.equal(B.decideStartBillingCycle(orgAdmin, "", "2027_H1").reason, "invalid_org");
  assert.equal(B.decideStartBillingCycle(orgAdmin, "o1/x", "2027_H1").reason, "invalid_org");
  assert.equal(B.decideStartBillingCycle(orgAdmin, "o1", "").reason, "invalid_cycle");
  assert.equal(B.decideStartBillingCycle(orgAdmin, "o1", "2027/H1").reason, "invalid_cycle");
  assert.equal(B.decideStartBillingCycle(orgAdmin, "o1", "../x").reason, "invalid_cycle");
  assert.equal(B.billingRunId("o1", "2027_H1"), "o1_2027_H1");
});

test("skipReasonForDelegate treats approved as active and skips app, paid, and held docs", () => {
  const path = "organizations/o1/companies/c1/delegates/d1";
  const period = "2027_H1";
  const none = new Set();
  const web = {uid: "d1", status: "active", source: "web"};
  assert.equal(B.skipReasonForDelegate(path, web, "o1", period, none, none), null);
  assert.equal(B.skipReasonForDelegate(path, {...web, status: "approved"}, "o1", period, none, none), null);

  assert.equal(B.skipReasonForDelegate(path, {...web, status: "pending"}, "o1", period, none, none), "status_not_actionable");
  assert.equal(B.skipReasonForDelegate(path, {...web, status: "rejected"}, "o1", period, none, none), "status_not_actionable");
  assert.equal(B.skipReasonForDelegate(path, {...web, status: "suspended"}, "o1", period, none, none), "already_suspended");
  assert.equal(
    B.skipReasonForDelegate(path, {...web, source: "app"}, "o1", period, none, none),
    "source_app",
  );
  assert.equal(
    B.skipReasonForDelegate(path, {uid: "d1", status: "active", delegateSource: "app"}, "o1", period, none, none),
    "source_app",
  );
  assert.equal(
    B.skipReasonForDelegate(path, web, "o1", period, new Set(["d1"]), none),
    "app_added_request",
  );
  assert.equal(
    B.skipReasonForDelegate(path, web, "o1", period, none, new Set(["d1"])),
    "paid_coverage",
  );
  assert.equal(
    B.skipReasonForDelegate(path, {
      ...web,
      subscription: {periodCode: "2027_H1", paymentStatus: "paid"},
    }, "o1", period, none, none),
    "paid_subscription",
  );
  assert.equal(
    B.skipReasonForDelegate(path, {
      ...web,
      subscription: {periodCode: "2027_H1", paymentStatus: "waived"},
    }, "o1", period, none, none),
    "paid_subscription",
  );
  assert.equal(
    B.skipReasonForDelegate(path, {
      ...web,
      subscription: {periodCode: "2026_H2", paymentStatus: "paid"},
    }, "o1", period, none, none),
    null,
  );
  assert.equal(
    B.skipReasonForDelegate(path, {
      ...web,
      holds: {billing_cycle_reset: {at: "t", by: "x"}},
    }, "o1", period, none, none),
    "already_held",
  );
  assert.equal(
    B.skipReasonForDelegate("organizations/o2/companies/c1/delegates/d1", web, "o1", period, none, none),
    "wrong_org",
  );
});

test("subscriptionPaidForPeriod requires the current period", () => {
  assert.equal(B.subscriptionPaidForPeriod({periodCode: "2027_H1", paymentStatus: "paid"}, "2027_H1"), true);
  assert.equal(B.subscriptionPaidForPeriod({periodCode: "2027_H1", paymentStatus: "pending"}, "2027_H1"), false);
  assert.equal(B.subscriptionPaidForPeriod({periodCode: "2027_H2", paymentStatus: "paid"}, "2027_H1"), false);
  assert.equal(B.subscriptionPaidForPeriod(null, "2027_H1"), false);
});

test("claimBillingRun creates, resumes, no-ops when done, and rejects a live foreign lease", () => {
  const base = {
    orgId: "o1",
    cycleId: "2027_H1",
    periodCode: "2027_H1",
    actor: "oa1",
    mode: "shadow",
    nowMs: 1_000_000,
    at: "2027-01-02T00:00:00.000Z",
  };
  const created = B.claimBillingRun(null, base);
  assert.equal(created.action, "create");
  assert.equal(created.state.state, "running");
  assert.equal(created.state.phase, "companies");
  assert.equal(created.state.cursor, "");

  const mid = {
    ...created.state,
    phase: "delegates",
    cursor: "organizations/o1/companies/c1/delegates/d10",
    actor: "oa1",
    leaseUntil: 900_000,
    counts: {docs: 10, companies: 2, companiesReset: 2, written: 3, skipped: 1, byReason: {source_app: 1}},
  };
  const resumed = B.claimBillingRun(mid, {...base, nowMs: 1_000_000, actor: "oa1"});
  assert.equal(resumed.action, "resume");
  assert.equal(resumed.state.cursor, mid.cursor);
  assert.equal(resumed.state.counts.written, 3);

  const busy = B.claimBillingRun(
    {...mid, leaseUntil: 2_000_000, actor: "other"},
    {...base, actor: "oa1", nowMs: 1_000_000},
  );
  assert.equal(busy.action, "in_progress");

  const takeover = B.claimBillingRun(
    {...mid, leaseUntil: 500_000, actor: "other"},
    {...base, actor: "oa1", nowMs: 1_000_000},
  );
  assert.equal(takeover.action, "resume");
  assert.equal(takeover.state.actor, "oa1");

  const done = B.finishBillingRun(mid, "2027-01-02T00:01:00.000Z", 1_000_000);
  assert.equal(done.state, "done");
  const noop = B.claimBillingRun(done, base);
  assert.equal(noop.action, "noop_done");
});

test("periodCodeAt uses the Cairo period and companyResetData clears deferred counters", () => {
  assert.equal(B.periodCodeAt(new Date("2027-02-01T10:00:00+02:00")), "2027_H1");
  assert.equal(B.periodCodeAt(new Date("2027-07-01T00:00:00+03:00")), periodOf(new Date("2027-07-01T00:00:00+03:00")).code);
  assert.deepEqual(B.companyResetData(), {
    deferredPayment: 0,
    hasDeferredPayment: false,
    totalApprovedDelegates: 0,
  });
});
