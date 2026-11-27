// TAS-361 phase 2: decisions of delegateCheckIn / delegateCheckOut (pure logic).
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/attendance_callables_logic");

const BRANCH = {location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100};
const TOKEN = {role: "delegate", delegateId: "d1", orgId: "o1", orgIds: ["o1", "o2"]};
const NOW = Date.parse("2026-11-27T10:00:00Z"); // 12:00 Cairo
const HOUR = 3600 * 1000;
const input = (extra = {}) => L.parseCheckIn({organizationId: "o1", companyId: "c1", branchId: "b1",
  requestId: "req-000001", lat: 30.0449, lng: 31.2357, branchName: "Fake Alpha", ...extra});
const log = (extra = {}) => ({id: "x", type: "check_in", atMs: NOW - HOUR, branchId: "b1",
  branchOrganizationUID: "o1", branchName: "Fake Alpha", closed: false, ...extra});
const decide = (over = {}) => L.decideCheckIn({input: input(), token: TOKEN, membership: {status: "active"},
  branch: BRANCH, recent: [], nowMs: NOW, ...over});

test("inside the branch is accepted with the distance", () => {
  const d = decide();
  assert.equal(d.ok, true);
  assert.ok(d.distanceMeters > 50 && d.distanceMeters < 60);
  assert.equal(d.allowedMeters, 150);
});

test("outside radius+50 is refused with distance and allowed meters", () => {
  const d = decide({input: input({lat: 30.0464})});
  assert.equal(d.reason, "outside_branch");
  assert.ok(d.distanceMeters > 200);
  assert.equal(d.allowedMeters, 150);
  assert.match(d.message, /برّه نطاق الفرع/);
});

test("request shape: no branchId, no ids, bad requestId", () => {
  assert.equal(L.parseCheckIn({organizationId: "o1", companyId: "c1", requestId: "req-000001"}).reason, "no_branch");
  assert.equal(L.parseCheckIn({branchId: "b1", requestId: "req-000001"}).reason, "bad_request");
  assert.equal(input({requestId: "a/b"}).reason, "bad_request");
});

test("branch missing, at 0,0, of another chain, no position", () => {
  assert.equal(decide({branch: null}).reason, "branch_not_found");
  assert.equal(decide({branch: {location: {latitude: 0, longitude: 0}}}).reason, "branch_without_location");
  assert.equal(decide({input: input({branchOrganizationUID: "o9"})}).reason, "branch_other_chain");
  assert.equal(decide({input: input({organizationId: "o9"})}).reason, "branch_other_chain");
  assert.equal(decide({input: input({lat: 0, lng: 0})}).reason, "no_position");
  assert.equal(decide({input: input({lat: null})}).reason, "no_position");
});

test("staff token and non-member are refused", () => {
  assert.equal(decide({token: {role: "hr", orgId: "o1"}}).reason, "not_delegate");
  assert.equal(decide({membership: null}).reason, "not_member");
  assert.equal(decide({membership: {status: "deleted"}}).reason, "not_member");
});

test("one open session: same branch / other branch, even from yesterday", () => {
  assert.equal(decide({recent: [log()]}).reason, "open_session_same_branch");
  const other = decide({recent: [log({branchId: "b2", branchName: "Fake Beta"})]});
  assert.equal(other.reason, "open_session_other_branch");
  assert.equal(other.branchName, "Fake Beta");
  // Opened 10 h ago, yesterday evening in Cairo: still the open session.
  assert.equal(decide({recent: [log({atMs: NOW - 10 * HOUR, branchId: "b2"})]}).reason,
    "open_session_other_branch");
});

test("a forgotten session older than 11.5 h does not block (TAS-362 closes it)", () => {
  assert.equal(decide({recent: [log({atMs: NOW - 12 * HOUR, branchId: "b2"})]}).ok, true);
});

test("same branch twice the same Cairo day is refused; other branch or other day is fine", () => {
  assert.equal(decide({recent: [log({closed: true})]}).reason, "same_branch_today");
  assert.equal(decide({recent: [log({closed: true, branchId: "b2"})]}).ok, true);
  // 23:30 Cairo yesterday vs 12:00 today.
  const yesterday = Date.parse("2026-11-26T21:30:00Z");
  assert.equal(decide({recent: [log({closed: true, atMs: yesterday})]}).ok, true);
  // Legacy log without branchId: compared by name.
  assert.equal(decide({recent: [log({closed: true, branchId: ""})]}).reason, "same_branch_today");
});

test("cairoDay follows Africa/Cairo", () => {
  assert.equal(L.cairoDay(Date.parse("2026-11-26T22:30:00Z")), "2026-11-27");
  assert.equal(L.cairoDay(Date.parse("2026-11-26T21:30:00Z")), "2026-11-26");
});

test("check-in doc: identity from the token, never from the request", () => {
  const doc = L.buildCheckInDoc(input({delegateId: "someone-else"}), "d1");
  assert.equal(doc.delegateId, "d1");
  assert.equal(doc.userId, "d1");
  assert.equal(doc.type, "check_in");
  assert.equal(doc.branchOrganizationUID, "o1");
  assert.equal(doc.source, "server");
  assert.equal(doc.checkOutTime, undefined);
});

test("check-out: owner only, idempotent retry, already closed refused", () => {
  const rec = {type: "check_in", delegateId: "d1"};
  const co = (record, extra = {}) => L.decideCheckOut({attendanceId: "a1", record, selfIds: ["d1"],
    token: TOKEN, ...extra});
  assert.deepEqual(co(rec), {ok: true, already: false});
  assert.equal(co(null).reason, "record_not_found");
  assert.equal(co({type: "check_out", delegateId: "d1"}).reason, "record_not_found");
  assert.equal(co({...rec, delegateId: "d2"}).reason, "not_owner");
  assert.equal(co(rec, {token: {role: "hr"}}).reason, "not_delegate");
  assert.deepEqual(co({...rec, checkOutTime: 1, checkOutDocId: "a1_out"}), {ok: true, already: true});
  assert.equal(co({...rec, checkOutTime: 1, checkOutDocId: "other"}).reason, "already_checked_out");
  // Legacy record keyed by userId.
  assert.deepEqual(co({type: "check_in", userId: "d1"}), {ok: true, already: false});
});

test("check-out distance never refuses: outside is a flag", () => {
  assert.deepEqual(L.checkOutDistance(30.0444, 31.2357, BRANCH), {distanceMeters: 0, outside: false});
  const far = L.checkOutDistance(30.0544, 31.2357, BRANCH);
  assert.equal(far.outside, true);
  assert.deepEqual(L.checkOutDistance(null, null, BRANCH), {distanceMeters: null, outside: false});
  assert.deepEqual(L.checkOutDistance(30.05, 31.2, null), {distanceMeters: null, outside: false});
});
