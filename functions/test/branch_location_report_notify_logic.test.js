// TAS-397: who hears about a «مكان الفرع غلط» report.
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/branch_location_report_notify_logic");

const open = {status: "open", delegateId: "d1", delegateName: "مندوب تجريبي", branchId: "b1",
  branchName: "فرع التجربة", companyUID: "c1", organizationUID: "o1"};
const at = (status, extra = {}) => ({...open, status, ...extra});

test("events: opened, forwarded, rejected, fixed; nothing else", () => {
  assert.equal(L.reportEvent(undefined, open), "opened");
  assert.equal(L.reportEvent(at("rejected"), open), "opened", "reopened after a rejection");
  assert.equal(L.reportEvent(at("fixed"), open), "opened", "reopened after a fix");
  assert.equal(L.reportEvent(open, at("forwarded")), "forwarded");
  assert.equal(L.reportEvent(open, at("rejected")), "rejected");
  assert.equal(L.reportEvent(at("forwarded"), at("rejected")), "rejected");
  assert.equal(L.reportEvent(at("forwarded"), at("fixed")), "fixed");
  assert.equal(L.reportEvent(open, open), null, "no status move");
  assert.equal(L.reportEvent(open, undefined), null, "deleted");
  assert.equal(L.reportEvent(open, at("fixed")), null, "open -> fixed is not a real move");
});

test("audiences: supervisors on open; chain admins + delegate on forward; delegate on close", () => {
  assert.deepEqual(L.audiencesFor("opened"), ["company_supervisors"]);
  assert.deepEqual(L.audiencesFor("forwarded"), ["chain_admins", "delegate"]);
  assert.deepEqual(L.audiencesFor("rejected"), ["delegate"]);
  assert.deepEqual(L.audiencesFor("fixed"), ["delegate"]);
});

test("only active staff with the role; HR and supervisor-delegates never", () => {
  const uids = L.activeStaffUids([
    {uid: "sup", role: "supervisor"},
    {uid: "ca", role: "company-admin"},
    {uid: "hr", role: "hr"},
    {uid: "del", role: "delegate"},
    {uid: "off", role: "supervisor", status: "suspended"},
    {uid: "gone", role: "admin", isActive: false},
  ], L.COMPANY_SUPERVISOR_ROLES);
  assert.deepEqual(uids, ["ca", "sup"]);
});

test("one personal notification per recipient, fixed id, both org spellings", () => {
  const ns = L.notificationsFor("opened", "company_supervisors", "d1_b1", "evt/1", open, ["sup", "ca"]);
  assert.equal(ns.length, 2);
  assert.equal(ns[0].id, "blr_d1_b1_evt1_sup");
  assert.equal(ns[0].doc.delegateUid, "sup");
  assert.equal(ns[0].doc.organizationUID, "o1");
  assert.equal(ns[0].doc.organizationId, "o1");
  assert.equal(ns[0].doc.companyUID, "c1");
  assert.equal(ns[0].doc.type, "branch_location_report");
  assert.equal(ns[0].doc.createdBy, "system");
  assert.match(ns[0].doc.body, /فرع التجربة/);
});

test("the delegate's rejection carries the reason", () => {
  const [n] = L.notificationsFor("rejected", "delegate", "d1_b1", "e2", at("rejected", {rejectReason: "إنت بعيد"}), ["d1"]);
  assert.equal(n.doc.delegateUid, "d1");
  assert.match(n.doc.body, /إنت بعيد/);
  assert.equal(n.doc.reportStatus, "rejected");
});
