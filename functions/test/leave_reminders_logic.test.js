// TAS-370 (L-4): which leave requests get a reminder, and to whom (pure logic).
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/leave_reminders_logic");

const NOW = Date.parse("2026-12-02T10:00:00Z");
const H = 3600 * 1000;
const pending = {status: "pending", companyUID: "c1", organizationUID: "o1", delegateUid: "d1", delegateName: "Fake One"};

test("pending for 24 h or more is overdue; younger, resolved or undated is not", () => {
  assert.equal(L.isOverdue(pending, NOW - 25 * H, NOW), true);
  assert.equal(L.isOverdue(pending, NOW - 24 * H, NOW), true);
  assert.equal(L.isOverdue(pending, NOW - 23 * H, NOW), false);
  assert.equal(L.isOverdue({...pending, status: "approved"}, NOW - 48 * H, NOW), false);
  assert.equal(L.isOverdue({...pending, status: "rejected"}, NOW - 48 * H, NOW), false);
  assert.equal(L.isOverdue(pending, null, NOW), false);
});

test("supervisor broadcast plus one per HR user, fixed ids, no duplicates", () => {
  const out = L.reminderNotifications("l1", pending, ["hr2", "hr1", "hr2", ""]);
  assert.deepEqual(out.map((n) => n.id), ["leave_reminder_l1", "leave_reminder_l1_hr1", "leave_reminder_l1_hr2"]);
  assert.equal(out[0].doc.delegateUid, "supervisor_c1");
  assert.equal(out[1].doc.delegateUid, "hr1");
  assert.equal(out[1].doc.type, "leave_request_reminder");
  assert.equal(out[1].doc.leaveRequestId, "l1");
  assert.match(out[1].doc.body, /Fake One/);
});

test("no company, no reminder", () => {
  assert.deepEqual(L.reminderNotifications("l1", {...pending, companyUID: ""}, ["hr1"]), []);
});

test("HR users: role hr (any case), active only", () => {
  assert.equal(L.isActiveHr({role: "hr"}), true);
  assert.equal(L.isActiveHr({role: "HR", status: "active"}), true);
  assert.equal(L.isActiveHr({role: "hr", status: "suspended"}), false);
  assert.equal(L.isActiveHr({role: "accountant"}), false);
});
