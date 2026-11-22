const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/penalty_notify_logic");

const users = [
  {id: "oa1", data: {role: "organizationAdmin", organizationUID: "o1", phoneNumber: "0100"}},
  {id: "oa2", data: {role: "organization-admin", organizationUIDs: ["o2", "o1"]}},
  {id: "bmm", data: {role: "branches_marketing", organizationUID: "o1"}},
  {id: "sa", data: {role: "super-admin", organizationUID: "o1"}},
  {id: "tech", data: {role: "technicalSupport", organizationUID: "o1"}},
  {id: "hr", data: {role: "hr", organizationUID: "o1"}},
  {id: "oaOther", data: {role: "organizationAdmin", organizationUID: "o2"}},
];

const ids = (rs) => rs.map((r) => r.uid).sort();

test("normal penalty: org admins, super admins and BMM of the penalty org", () => {
  const rs = L.penaltyManagerRecipients(users, {organizationId: "o1", isConfidential: false});
  assert.deepEqual(ids(rs), ["bmm", "oa1", "oa2", "sa"]);
  assert.equal(rs.find((r) => r.uid === "bmm").isBmm, true);
  assert.equal(rs.find((r) => r.uid === "oa1").phone, "0100");
});

test("confidential penalty: no BMM, technical support included", () => {
  const rs = L.penaltyManagerRecipients(users, {organizationId: "o1", isConfidential: true});
  assert.deepEqual(ids(rs), ["oa1", "oa2", "sa", "tech"]);
});

test("other organizations, duplicates and the creator are left out", () => {
  const dup = [...users, users[0]];
  const rs = L.penaltyManagerRecipients(dup, {organizationId: "o1", createdById: "oa2"});
  assert.deepEqual(ids(rs), ["bmm", "oa1", "sa"]);
});

test("no organization on the penalty: nobody (the role broadcasts still go)", () => {
  assert.deepEqual(L.penaltyManagerRecipients(users, {}), []);
  assert.equal(L.penaltyOrganizationId({organizationUID: " o9 "}), "o9");
});

test("messages keep the app's wording and the 1000 limit for BMM", () => {
  const p = {title: "تأخير", fineAmount: 500, targetDelegateName: "أحمد", companyName: "شركة", branchName: "فرع"};
  assert.match(L.penaltyManagerMessage(p, true).body, /ضمن صلاحية اعتمادك/);
  assert.match(L.penaltyManagerMessage({...p, fineAmount: 1500}, true).body, /تمريرها للمدير العام/);
  assert.equal(L.penaltyManagerMessage(p, false).title, "إشعار تسجيل مخالفة جديدة على النظام");
  assert.equal(L.penaltyManagerMessage({...p, isConfidential: true}, false).title,
    "إشعار تسجيل مخالفة سرية على النظام");
  assert.match(L.penaltyManagerMessage({title: "x"}, false).body, /المندوب \(المندوب\).*الفرع المحدد/);
});

test("notification doc targets the manager and has a stable id", () => {
  const doc = L.penaltyManagerNotification("p1", {companyId: "c1", fineAmount: 10},
    {uid: "oa1", isBmm: false, phone: "0100"});
  assert.equal(doc.delegateUid, "oa1");
  assert.equal(doc.type, "penalty");
  assert.equal(doc.penaltyId, "p1");
  assert.equal(doc.phoneNumber, "0100");
  assert.equal(L.penaltyManagerNotificationId("p1", "oa1"), "penalty_p1_mgr_oa1");
});
