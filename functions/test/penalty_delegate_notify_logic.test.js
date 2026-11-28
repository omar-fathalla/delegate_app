// TAS-365: which penalty changes the delegate hears about, and the old-app dedupe.
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/penalty_delegate_notify_logic");

const base = {
  title: "تأخير", fineAmount: 200, targetDelegateId: "d1", targetDelegateName: "Fake Delegate",
  createdByName: "Fake Supervisor", organizationId: "o1", companyId: "c1", companyName: "Fake Co",
};
const at = (status, extra = {}) => ({...base, status, ...extra});

test("created PENDING: nothing for the delegate; created ISSUED: one", () => {
  assert.equal(L.delegatePenaltyEvent(null, at("PENDING_BRANCHES_MARKETING")), null);
  assert.equal(L.delegatePenaltyEvent(null, at("ISSUED")), "issued");
  const n = L.delegatePenaltyNotification("p1", null, at("ISSUED"));
  assert.equal(n.id, "penalty_p1_del_issued");
  assert.equal(n.doc.delegateUid, "d1");
  assert.equal(n.doc.title, "عليك جزاء جديد");
  assert.match(n.doc.body, /200 ج، من Fake Supervisor/);
  assert.match(n.doc.body, /خلال 3 أيام/);
  assert.equal(n.doc.organizationId, "o1");
  assert.equal(n.doc.organizationUID, "o1");
  assert.equal(n.doc.createdBy, "system");
});

test("update to ISSUED: issued; no status move: nothing", () => {
  assert.equal(L.delegatePenaltyEvent(at("PENDING_GENERAL_MANAGER"), at("ISSUED")), "issued");
  assert.equal(L.delegatePenaltyEvent(at("ISSUED"), at("ISSUED", {title: "x"})), null);
  assert.equal(L.delegatePenaltyEvent(at("ISSUED"), at("ACKNOWLEDGED")), null);
  assert.equal(L.delegatePenaltyEvent(at("PENDING_BRANCHES_MARKETING"), at("REJECTED_BRANCHES_MARKETING")), null,
    "never heard of it: no rejection notice");
});

test("dispute results, cancel and deduct", () => {
  assert.equal(L.delegatePenaltyEvent(at("DISPUTED"), at("ISSUED")), "dispute_rejected");
  assert.equal(L.delegatePenaltyEvent(at("DISPUTED"), at("CANCELLED")), "dispute_accepted");
  assert.equal(L.delegatePenaltyEvent(at("ISSUED"), at("CANCELLED")), "cancelled");
  assert.equal(L.delegatePenaltyEvent(at("PENDING_GENERAL_MANAGER"), at("CANCELLED")), null);
  assert.equal(L.delegatePenaltyEvent(at("ACKNOWLEDGED"), at("DEDUCTED")), "deducted");
  const r = L.delegatePenaltyNotification("p2", at("DISPUTED"),
    at("ISSUED", {disputeResolutionReason: "الكاميرا واضحة"}));
  assert.equal(r.id, "penalty_p2_del_dispute_rejected");
  assert.equal(r.doc.title, "اعتراضك اترفض");
  assert.match(r.doc.body, /السبب: الكاميرا واضحة/);
  assert.equal(L.delegatePenaltyNotification("p2", at("DISPUTED"), at("CANCELLED")).doc.title,
    "اعتراضك اتقبل والجزاء اتلغى");
});

test("confidential penalties still reach the delegate", () => {
  assert.ok(L.delegatePenaltyNotification("p3", null, at("ISSUED", {isConfidential: true})));
});

test("no delegate, no notification", () => {
  assert.equal(L.delegatePenaltyNotification("p4", null, at("ISSUED", {targetDelegateId: ""})), null);
});

test("dispute opened is told to the deciders", () => {
  assert.equal(L.disputeOpened(at("ISSUED"), at("DISPUTED")), true);
  assert.equal(L.disputeOpened(at("DISPUTED"), at("DISPUTED")), false);
  assert.equal(L.disputeOpened(null, at("DISPUTED")), false);
  const d = L.disputeOpenedNotification("p5", at("DISPUTED", {disputeReason: "كنت في إجازة"}), "admin1");
  assert.equal(d.delegateUid, "admin1");
  assert.match(d.body, /كنت في إجازة/);
});

test("server marker: notifyByServerAt equal to updatedAt", () => {
  const ts = (s) => ({seconds: s, nanoseconds: 0, isEqual(o) { return o && o.seconds === s; }});
  assert.equal(L.changeMarkedForServer({updatedAt: ts(5), notifyByServerAt: ts(5)}), true);
  assert.equal(L.changeMarkedForServer({updatedAt: ts(6), notifyByServerAt: ts(5)}), false,
    "a later old-app write keeps the old marker but moves updatedAt");
  assert.equal(L.changeMarkedForServer({updatedAt: ts(5)}), false);
});

test("old-app dedupe: a fresh client notification for the same delegate", () => {
  const since = 1000;
  assert.equal(L.clientAlreadyNotified([{delegateUid: "d1", createdAtMs: 1500}], "d1", since), true);
  assert.equal(L.clientAlreadyNotified([{delegateUid: "d1", createdAtMs: 500}], "d1", since), false, "older event");
  assert.equal(L.clientAlreadyNotified([{delegateUid: "mgr", createdAtMs: 1500}], "d1", since), false);
  assert.equal(L.clientAlreadyNotified([], "d1", since), false);
});
