// TAS-371: which leave / device-change decisions the server announces.
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/request_decision_notify_logic");

const pending = {status: "pending", delegateUid: "d1", organizationUID: "o1", companyUID: "c1"};
const decided = (status, extra = {}) => ({...pending, status, notifyByServer: true, resolvedByName: "Fake HR", ...extra});

test("only pending → approved / rejected with the marker", () => {
  assert.equal(L.decidedStatus(pending, decided("approved")), "approved");
  assert.equal(L.decidedStatus(pending, decided("rejected")), "rejected");
  assert.equal(L.decidedStatus(pending, {...decided("approved"), notifyByServer: undefined}), null, "old staff app: it notifies itself");
  assert.equal(L.decidedStatus(decided("approved"), decided("approved")), null, "no move");
  assert.equal(L.decidedStatus(decided("approved"), decided("rejected")), null, "not from pending");
  assert.equal(L.decidedStatus(pending, {...pending, notifyByServer: true}), null, "still pending");
});

test("fixed id per request and status; both org spellings; system author", () => {
  const n = L.decisionNotification("leave", "l1", pending, decided("approved"));
  assert.equal(n.id, "leave_l1_approved");
  assert.equal(n.doc.delegateUid, "d1");
  assert.equal(n.doc.organizationUID, "o1");
  assert.equal(n.doc.organizationId, "o1");
  assert.equal(n.doc.companyUID, "c1");
  assert.equal(n.doc.type, "leave_approved");
  assert.equal(n.doc.createdBy, "system");
  assert.equal(n.doc.senderName, "Fake HR");
});

test("rejections carry the reason", () => {
  const l = L.decisionNotification("leave", "l2", pending, decided("rejected", {rejectReason: "ضغط شغل"}));
  assert.equal(l.doc.type, "leave_rejected");
  assert.match(l.doc.body, /ضغط شغل/);
  const u = L.decisionNotification("unbind", "u1", pending, decided("rejected", {rejectReason: "مش نفس الشخص"}));
  assert.equal(u.id, "unbind_u1_rejected");
  assert.equal(u.doc.type, "device_unbind_rejected");
  assert.equal(u.doc.body, "مش نفس الشخص");
  assert.equal(L.decisionNotification("unbind", "u2", pending, decided("approved")).doc.type, "device_unbound");
});

test("no delegate, no notification", () => {
  assert.equal(L.decisionNotification("leave", "l3", pending, decided("approved", {delegateUid: ""})), null);
});
