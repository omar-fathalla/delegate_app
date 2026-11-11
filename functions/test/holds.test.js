const test = require("node:test");
const assert = require("node:assert/strict");
const H = require("../lib/holds");

const at = "2026-11-11T04:00:00.000Z";

test("deriveStatus: pending and rejected stay, approved reads as active", () => {
  assert.equal(H.deriveStatus("pending", {}), "pending");
  assert.equal(H.deriveStatus("rejected", {[H.HOLD_ADMIN_SUSPEND]: {at}}), "rejected");
  assert.equal(H.deriveStatus("approved", {}), "active");
  assert.equal(H.deriveStatus("active", {}), "active");
  assert.equal(H.deriveStatus("active", {[H.HOLD_SUBSCRIPTION_EXPIRED]: {at}}), "suspended");
  assert.equal(H.deriveStatus("Approved", {}), "active");
});

test("statusReason priority: admin_suspend > subscription_expired > billing_cycle_reset", () => {
  const holds = {
    [H.HOLD_BILLING_CYCLE_RESET]: {at},
    [H.HOLD_SUBSCRIPTION_EXPIRED]: {at},
    [H.HOLD_ADMIN_SUSPEND]: {at},
  };
  assert.equal(H.statusReasonFromHolds(holds), H.HOLD_ADMIN_SUSPEND);
  const withoutAdmin = {...holds};
  delete withoutAdmin[H.HOLD_ADMIN_SUSPEND];
  assert.equal(H.statusReasonFromHolds(withoutAdmin), H.HOLD_SUBSCRIPTION_EXPIRED);
  assert.equal(H.statusReasonFromHolds({[H.HOLD_BILLING_CYCLE_RESET]: {at}}), H.HOLD_BILLING_CYCLE_RESET);
  assert.equal(H.statusReasonFromHolds({}), null);
});

test("holdsMode defaults to shadow unless HOLDS_AUTHORITY_MODE=authoritative", () => {
  assert.equal(H.holdsMode({}), "shadow");
  assert.equal(H.holdsMode({HOLDS_AUTHORITY_MODE: "shadow"}), "shadow");
  assert.equal(H.holdsMode({HOLDS_AUTHORITY_MODE: "nope"}), "shadow");
  assert.equal(H.holdsMode({HOLDS_AUTHORITY_MODE: "Authoritative"}), "shadow");
  assert.equal(H.holdsMode({HOLDS_AUTHORITY_MODE: "authoritative"}), "authoritative");
});

test("authorityStatusFields writes status only in authoritative; rollback is one step", () => {
  const derived = "suspended";
  const reason = H.HOLD_ADMIN_SUSPEND;
  assert.equal(H.authorityStatusFields("shadow", derived, reason), null);
  assert.equal(H.authorityStatusFields("nope", derived, reason), null);
  assert.equal(H.authorityStatusFields("", derived, reason), null);
  assert.equal(H.authorityStatusFields(H.holdsMode({}), derived, reason), null);
  assert.deepEqual(
    H.authorityStatusFields("authoritative", derived, reason),
    {status: "suspended", statusReason: reason},
  );
  assert.deepEqual(
    H.authorityStatusFields("authoritative", "active", null),
    {status: "active", statusReason: null},
  );
  // One-step rollback: after a flip, any non-authoritative env is shadow again.
  const flipped = H.holdsMode({HOLDS_AUTHORITY_MODE: "authoritative"});
  assert.equal(flipped, "authoritative");
  assert.ok(H.authorityStatusFields(flipped, derived, reason));
  const rolled = H.holdsMode({HOLDS_AUTHORITY_MODE: "shadow"});
  assert.equal(rolled, "shadow");
  assert.equal(H.authorityStatusFields(rolled, derived, reason), null);
  const unset = H.holdsMode({});
  assert.equal(unset, "shadow");
  assert.equal(H.authorityStatusFields(unset, derived, reason), null);
});

test("planHoldChange in shadow does not change derived vs current status write", () => {
  const plan = H.planHoldChange({
    data: {status: "active", holds: {}, statusVersion: 1},
    op: "add",
    hold: H.HOLD_ADMIN_SUSPEND,
    actor: "sa1",
    mode: "shadow",
    at,
    note: "test",
  });
  assert.equal(plan.ok, true);
  assert.equal(plan.unchanged, undefined);
  assert.equal(plan.mode, "shadow");
  assert.equal(plan.derivedStatus, "suspended");
  assert.equal(plan.statusVersion, 2);
  assert.equal(plan.history.to, "active"); // shadow keeps current status in history.to
  assert.equal(plan.history.derivedStatus, "suspended");
  assert.equal(plan.history.holdAdded, H.HOLD_ADMIN_SUSPEND);
  assert.ok(plan.nextHolds.admin_suspend);
});

test("planHoldChange authoritative records the derived status as to", () => {
  const plan = H.planHoldChange({
    data: {status: "active"},
    op: "add",
    hold: H.HOLD_SUBSCRIPTION_EXPIRED,
    actor: "job",
    mode: "authoritative",
    at,
  });
  assert.equal(plan.history.to, "suspended");
  assert.equal(plan.derivedStatus, "suspended");
});

test("planHoldChange is idempotent when the hold is already present", () => {
  const plan = H.planHoldChange({
    data: {
      status: "suspended",
      statusVersion: 3,
      holds: {[H.HOLD_ADMIN_SUSPEND]: {at, by: "sa1"}},
    },
    op: "add",
    hold: H.HOLD_ADMIN_SUSPEND,
    actor: "sa1",
    mode: "shadow",
    at,
  });
  assert.equal(plan.ok, true);
  assert.equal(plan.unchanged, true);
  assert.equal(plan.statusVersion, 3);
});

test("planHoldChange refuses pending and rejected", () => {
  const pending = H.planHoldChange({
    data: {status: "pending"}, op: "add", hold: H.HOLD_ADMIN_SUSPEND,
    actor: "sa", mode: "shadow", at,
  });
  assert.equal(pending.ok, false);
  assert.equal(pending.reason, "status_not_actionable");
  const rejected = H.planHoldChange({
    data: {status: "rejected"}, op: "remove", hold: H.HOLD_ADMIN_SUSPEND,
    actor: "sa", mode: "shadow", at,
  });
  assert.equal(rejected.ok, false);
});

test("removing the last hold derives active; stacked holds stay suspended", () => {
  const stacked = {
    [H.HOLD_ADMIN_SUSPEND]: {at},
    [H.HOLD_SUBSCRIPTION_EXPIRED]: {at},
  };
  const afterAdmin = H.planHoldChange({
    data: {status: "suspended", holds: stacked, statusVersion: 1},
    op: "remove", hold: H.HOLD_ADMIN_SUSPEND, actor: "sa", mode: "shadow", at,
  });
  assert.equal(afterAdmin.derivedStatus, "suspended");
  assert.ok(afterAdmin.nextHolds.subscription_expired);
  const last = H.planHoldChange({
    data: {status: "suspended", holds: afterAdmin.nextHolds, statusVersion: 2},
    op: "remove", hold: H.HOLD_SUBSCRIPTION_EXPIRED, actor: "pay", mode: "shadow", at,
  });
  assert.equal(last.derivedStatus, "active");
  assert.equal(H.hasAnyHold(last.nextHolds), false);
});

test("decideSetDelegateHold: super / org / company scope and fail-closed company", () => {
  const target = {orgId: "o1", companyId: "c1"};
  const superAdmin = {uid: "s", role: "super-admin"};
  assert.equal(H.decideSetDelegateHold(superAdmin, target, "admin_suspend", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(superAdmin, target, "subscription_expired", "remove").ok, false);
  assert.equal(H.decideSetDelegateHold(superAdmin, target, "subscription_expired", "remove", "override").ok, true);

  const org = {uid: "oa", role: "organization-admin", organizationUID: "o1"};
  assert.equal(H.decideSetDelegateHold(org, target, "admin_suspend", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(org, target, "billing_cycle_reset", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(org, {orgId: "o2", companyId: "c1"}, "admin_suspend", "add").ok, false);
  assert.equal(H.decideSetDelegateHold(org, target, "subscription_expired", "remove", "no").reason, "hold_not_allowed");

  const co = {uid: "ca", role: "admin", organizationUID: "o1", companyUID: "c1"};
  assert.equal(H.decideSetDelegateHold(co, target, "admin_suspend", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(co, target, "billing_cycle_reset", "add").reason, "hold_not_allowed");
  const noCo = {uid: "ca", role: "company-admin", organizationUID: "o1", companyUID: ""};
  assert.equal(H.decideSetDelegateHold(noCo, target, "admin_suspend", "add").reason, "out_of_scope");
  const wrongCo = {uid: "ca", role: "admin", organizationUID: "o1", companyUID: "c2"};
  assert.equal(H.decideSetDelegateHold(wrongCo, target, "admin_suspend", "add").reason, "out_of_scope");

  const hr = {uid: "h", role: "hr", organizationUID: "o1", companyUID: "c1"};
  assert.equal(H.decideSetDelegateHold(hr, target, "admin_suspend", "add").reason, "caller_not_allowed");
  const sup = {uid: "v", role: "supervisor", organizationUID: "o1", companyUID: "c1"};
  assert.equal(H.decideSetDelegateHold(sup, target, "admin_suspend", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(sup, target, "billing_cycle_reset", "add").reason, "hold_not_allowed");
  const supAlias = {uid: "v2", role: "company_supervisor", organizationUID: "o1", companyUID: "c1"};
  assert.equal(H.decideSetDelegateHold(supAlias, target, "admin_suspend", "add").ok, true);
  const tech = {uid: "t", role: "technical-support"};
  assert.equal(H.decideSetDelegateHold(tech, target, "admin_suspend", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(tech, {orgId: "o2", companyId: "c9"}, "admin_suspend", "remove").ok, true);
  assert.equal(H.decideSetDelegateHold(tech, target, "billing_cycle_reset", "add").ok, true);
  assert.equal(H.decideSetDelegateHold(tech, target, "subscription_expired", "remove", "override").reason, "hold_not_allowed");
  assert.equal(H.decideSetDelegateHold(null, target, "admin_suspend", "add").reason, "caller_not_staff");
  assert.equal(H.decideSetDelegateHold({uid: "s", role: "admin", isActive: false, organizationUID: "o1", companyUID: "c1"}, target, "admin_suspend", "add").reason, "caller_inactive");
});

test("inferHoldsFromStatusReason maps web and mobile reasons", () => {
  const expired = H.inferHoldsFromStatusReason("suspended", "subscription_expired", at, "backfill");
  assert.ok(expired.subscription_expired);
  const billing = H.inferHoldsFromStatusReason("suspended", "billing_cycle_reset", at, "backfill");
  assert.ok(billing.billing_cycle_reset);
  const suspend = H.inferHoldsFromStatusReason("suspended", "suspend", at, "backfill");
  assert.ok(suspend.admin_suspend);
  const unknown = H.inferHoldsFromStatusReason("suspended", "", at, "backfill");
  assert.equal(unknown.admin_suspend.note, "backfill_unknown");
  assert.deepEqual(H.inferHoldsFromStatusReason("active", "suspend", at, "backfill"), {});
  assert.deepEqual(H.inferHoldsFromStatusReason("rejected", "some text", at, "backfill"), {});
});

test("inferRejectionReason copies free text only on rejected docs", () => {
  assert.equal(H.inferRejectionReason("rejected", "وثائق ناقصة", ""), "وثائق ناقصة");
  assert.equal(H.inferRejectionReason("rejected", "suspend", ""), "");
  assert.equal(H.inferRejectionReason("suspended", "وثائق ناقصة", ""), "");
  assert.equal(H.inferRejectionReason("rejected", "x", "kept"), "kept");
});

test("inferSource copies delegateSource when source is empty", () => {
  assert.equal(H.inferSource("app", ""), "app");
  assert.equal(H.inferSource("web", "app"), "app");
  assert.equal(H.inferSource("unknown", ""), "");
});

test("planBackfill is additive, skips status, and is idempotent", () => {
  const first = H.planBackfill({
    status: "suspended",
    statusReason: "subscription_expired",
    delegateSource: "app",
  }, at, "run-1");
  assert.equal(first.skip, false);
  assert.ok(first.fields.holds.subscription_expired);
  assert.equal(first.fields.source, "app");
  assert.equal(first.fields.statusVersion, 1);
  assert.equal(first.fields.holdsBackfillRunId, "run-1");
  assert.equal("status" in first.fields, false);
  assert.equal("statusReason" in first.fields, false);

  const again = H.planBackfill({
    status: "suspended",
    statusReason: "subscription_expired",
    holds: first.fields.holds,
    source: "app",
    statusVersion: 1,
  }, at, "run-2");
  assert.equal(again.skip, true);

  const rejected = H.planBackfill({
    status: "rejected",
    statusReason: "missing docs",
  }, at, "run-3");
  assert.equal(rejected.fields.rejectionReason, "missing docs");
  assert.equal("holds" in rejected.fields, false);
});

test("evaluateShadowAudit logs bypasses and authority writes, ignores unrelated updates", () => {
  const quiet = H.evaluateShadowAudit(
    {status: "active", fullName: "A"},
    {status: "active", fullName: "B"},
  );
  assert.equal(quiet.audit, false);

  const bypass = H.evaluateShadowAudit(
    {status: "active"},
    {status: "suspended", statusReason: "suspend"},
  );
  assert.equal(bypass.audit, true);
  assert.equal(bypass.viaAuthority, false);
  assert.equal(bypass.payload.mismatch, true);
  assert.equal(bypass.payload.derivedStatus, "active"); // no holds yet

  const authority = H.evaluateShadowAudit(
    {status: "active", holds: {}, holdsAuthorityAt: ""},
    {
      status: "active",
      holds: {[H.HOLD_ADMIN_SUSPEND]: {at}},
      holdsAuthorityAt: at,
      statusVersion: 2,
    },
  );
  assert.equal(authority.audit, true);
  assert.equal(authority.viaAuthority, true);
  assert.equal(authority.payload.mismatch, true); // shadow: status still active, holds say suspended
});
