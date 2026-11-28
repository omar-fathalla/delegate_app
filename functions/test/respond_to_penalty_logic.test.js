// TAS-365: respondToPenalty rules (acknowledge, dispute, resolve).
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/respond_to_penalty_logic");

const DAY = 24 * 60 * 60 * 1000;
const issuedMs = Date.UTC(2026, 10, 20, 10);
const now = issuedMs + DAY;
const penalty = (status, extra = {}) => ({
  status, targetDelegateId: "d1", organizationId: "o1", issuedAt: {seconds: issuedMs / 1000}, ...extra,
});
const delegate = {uid: "d1", delegateIds: ["d1"], token: {role: "delegate"}, name: ""};
const input = (action, extra = {}) => L.parseRespondInput({penaltyId: "p1", action, ...extra});

test("parse: action, reason length, decision", () => {
  assert.equal(L.parseRespondInput({penaltyId: "p1", action: "x"}).reason, "bad_action");
  assert.equal(L.parseRespondInput({action: "dispute"}).reason, "bad_penalty");
  assert.equal(L.parseRespondInput({penaltyId: "p1", action: "dispute", reason: "x".repeat(501)}).reason,
    "reason_too_long");
  assert.equal(L.parseRespondInput({penaltyId: "p1", action: "resolve"}).reason, "bad_decision");
  assert.equal(L.parseRespondInput({penaltyId: "p1", action: "resolve", decision: "cancel"}).decision, "cancel");
});

test("not the penalty's delegate", () => {
  const other = {...delegate, uid: "d2", delegateIds: ["d2"]};
  assert.equal(L.planResponse(input("acknowledge"), penalty("ISSUED"), other, now).reason, "not_owner");
  assert.equal(L.planResponse(input("dispute", {reason: "غلط"}), penalty("ISSUED"), other, now).reason, "not_owner");
});

test("owner by the delegateIds claim too", () => {
  const multi = {...delegate, uid: "auth1", delegateIds: ["auth1", "d1"]};
  assert.equal(L.planResponse(input("acknowledge"), penalty("ISSUED"), multi, now).status, "ACKNOWLEDGED");
});

test("acknowledge: ISSUED only, idempotent on ACKNOWLEDGED", () => {
  const p = L.planResponse(input("acknowledge"), penalty("ISSUED"), delegate, now);
  assert.equal(p.update.status, "ACKNOWLEDGED");
  assert.equal(L.planResponse(input("acknowledge"), penalty("ACKNOWLEDGED"), delegate, now).noop, true);
  assert.equal(L.planResponse(input("acknowledge"), penalty("PENDING_BRANCHES_MARKETING"), delegate, now).reason,
    "wrong_status");
});

test("dispute: reason required, from ISSUED or ACKNOWLEDGED, inside 3 days", () => {
  assert.equal(L.planResponse(input("dispute"), penalty("ISSUED"), delegate, now).reason, "reason_required");
  const ok = L.planResponse(input("dispute", {reason: "كنت في إجازة"}), penalty("ISSUED"), delegate, now);
  assert.equal(ok.update.status, "DISPUTED");
  assert.equal(ok.update.statusBeforeDispute, "ISSUED");
  assert.equal(ok.update.disputeReason, "كنت في إجازة");
  const ack = L.planResponse(input("dispute", {reason: "كنت في إجازة"}), penalty("ACKNOWLEDGED"), delegate, now);
  assert.equal(ack.update.status, "DISPUTED", "acknowledging does not lose the right to dispute");
  const late = L.planResponse(input("dispute", {reason: "كنت في إجازة"}), penalty("ISSUED"), delegate,
    issuedMs + 3 * DAY + 1);
  assert.equal(late.reason, "window_closed");
});

test("dispute: once, never on DEDUCTED or pending", () => {
  const r = {reason: "كنت في إجازة"};
  assert.equal(L.planResponse(input("dispute", r), penalty("DISPUTED"), delegate, now).reason, "already_disputed");
  assert.equal(L.planResponse(input("dispute", r),
    penalty("ISSUED", {disputedAt: {seconds: 1}, disputeResolution: "upheld"}), delegate, now).reason,
  "already_disputed", "second dispute after a rejected one");
  assert.equal(L.planResponse(input("dispute", r), penalty("DEDUCTED"), delegate, now).reason, "deducted");
  assert.equal(L.planResponse(input("dispute", r), penalty("PENDING_GENERAL_MANAGER"), delegate, now).reason,
    "wrong_status");
});

test("dispute window falls back to the approval time on old docs", () => {
  const old = penalty("ISSUED", {issuedAt: undefined, generalManagerApprovedAt: {seconds: issuedMs / 1000}});
  assert.equal(L.planResponse(input("dispute", {reason: "غلط"}), old, delegate, issuedMs + 4 * DAY).reason,
    "window_closed");
});

test("resolve: super admin or the chain's admin, DISPUTED only, reason required", () => {
  const sup = {uid: "s1", delegateIds: ["s1"], token: {role: "super-admin"}, name: "Fake Super"};
  const orgAdmin = {uid: "a1", delegateIds: ["a1"], token: {role: "organization-admin", orgId: "o1"}, name: "A"};
  const otherOrg = {...orgAdmin, token: {role: "organization-admin", orgId: "o2"}};
  const hr = {uid: "h1", delegateIds: ["h1"], token: {role: "hr", companyId: "c1"}, name: "H"};
  const d = penalty("DISPUTED");
  const uphold = input("resolve", {decision: "uphold", reason: "الدليل واضح"});
  assert.equal(L.planResponse(uphold, d, hr, now).reason, "not_decider");
  assert.equal(L.planResponse(uphold, d, otherOrg, now).reason, "not_decider");
  assert.equal(L.planResponse(uphold, d, delegate, now).reason, "not_decider");
  assert.equal(L.planResponse(uphold, penalty("ISSUED"), sup, now).reason, "not_disputed");
  assert.equal(L.planResponse(input("resolve", {decision: "uphold"}), d, sup, now).reason, "reason_required");
  const up = L.planResponse(uphold, d, orgAdmin, now);
  assert.equal(up.update.status, "ISSUED");
  assert.equal(up.update.deductionMonth, "2026-11");
  assert.equal(up.update.notifyByServerAt, L.NOW);
  const cancel = L.planResponse(input("resolve", {decision: "cancel", reason: "كان في إجازة"}), d, sup, now);
  assert.equal(cancel.update.status, "CANCELLED");
  assert.equal(cancel.update.deductionMonth, undefined);
});

test("deductionMonth is the Cairo month", () => {
  // 2026-11-30 23:30 UTC is already December 1st in Cairo (UTC+2).
  assert.equal(L.cairoMonth(Date.UTC(2026, 10, 30, 23, 30)), "2026-12");
  assert.equal(L.cairoMonth(Date.UTC(2026, 10, 30, 12)), "2026-11");
});

test("missing penalty", () => {
  assert.equal(L.planResponse(input("acknowledge"), null, delegate, now).reason, "not_found");
});
