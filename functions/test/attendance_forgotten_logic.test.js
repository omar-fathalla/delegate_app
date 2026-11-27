// TAS-362: which check-ins the hourly job marks (pure logic).
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/attendance_forgotten_logic");

const NOW = Date.parse("2026-12-02T10:00:00Z");
const H = 3600 * 1000;
const open = {type: "check_in", delegateId: "d1", organizationId: "o1", companyId: "c1", branchName: "Fake Alpha"};

test("window is [now-48h, now-11.5h]", () => {
  const w = L.window(NOW);
  assert.equal(NOW - w.fromMs, 48 * H);
  assert.equal(NOW - w.toMs, 11.5 * H);
});

test("open check-in older than 11.5 h is forgotten; younger is not", () => {
  assert.equal(L.isForgotten(open, NOW - 12 * H, NOW), true);
  assert.equal(L.isForgotten(open, NOW - 11 * H, NOW), false, "a shift crossing midnight is not cut early");
  assert.equal(L.isForgotten(open, null, NOW), false);
});

test("closed, already marked, auto-closed by an old build, or a check_out record: skipped", () => {
  const old = NOW - 20 * H;
  assert.equal(L.isForgotten({...open, checkOutTime: 1}, old, NOW), false);
  assert.equal(L.isForgotten({...open, missingCheckOut: true}, old, NOW), false);
  assert.equal(L.isForgotten({...open, isAutoCheckOut: true}, old, NOW), false);
  assert.equal(L.isForgotten({...open, type: "check_out"}, old, NOW), false);
});

test("one notification per session, to the delegate, with the branch", () => {
  const n = L.notificationFor("a1", open);
  assert.equal(n.id, "missing_checkout_a1");
  assert.equal(n.doc.delegateUid, "d1");
  assert.equal(n.doc.type, "attendance_missing_checkout");
  assert.match(n.doc.body, /Fake Alpha/);
  assert.equal(L.notificationFor("a2", {type: "check_in"}), null);
  assert.equal(L.notificationFor("a3", {...open, delegateId: "", userId: "u9"}).doc.delegateUid, "u9");
});

test("mark fields: no check-out time (zero hours)", () => {
  const m = L.markFields();
  assert.equal(m.missingCheckOut, true);
  assert.equal(m.checkOutTime, undefined);
});
