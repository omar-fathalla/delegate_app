// TAS-361 phase 1: server verdict for attendance_logs (pure logic, no emulator).
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/attendance_verify_logic");

// Fake branch in Cairo; 0.001 deg latitude ~= 111 m. Limit = 100 + 50 m.
const BRANCH = {location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100};
const pos = (dLat) => ({latitude: 30.0444 + dLat, longitude: 31.2357});
const checkIn = (extra = {}) => ({
  type: "check_in", delegateId: "d1", organizationId: "o1", branchId: "b1",
  branchOrganizationUID: "o1", location: pos(0.0005), ...extra,
});
const apply = (after, before = null, branch = BRANCH) => {
  const plan = L.planVerification(before, after);
  return {plan, update: L.verificationUpdate(after, plan, branch)};
};

test("check-in inside the branch: distance stamped, inside", () => {
  const {plan, update} = apply(checkIn());
  assert.deepEqual(plan, {checkIn: true, checkOut: false});
  assert.equal(update.verifiedInsideBranch, true);
  assert.equal(update.verifiedReason, "ok");
  assert.equal(update.verifiedBranchRadius, 100);
  assert.ok(update.verifiedDistanceMeters > 50 && update.verifiedDistanceMeters < 60);
  assert.equal(update.checkOutOutsideBranch, undefined, "a check-in is not a check-out");
});

test("check-out stamped on the check-in, outside radius+50 -> flagged, not rejected", () => {
  const before = {...checkIn(), verifiedFor: L.signature(L.checkInPosition(checkIn()), checkIn())};
  const after = {...before, checkOutTime: "ts", checkOutLocation: pos(0.002)}; // ~222 m
  const {plan, update} = apply(after, before);
  assert.deepEqual(plan, {checkIn: false, checkOut: true});
  assert.equal(update.checkOutOutsideBranch, true);
  assert.ok(update.checkOutVerifiedDistanceMeters > 200);
  assert.equal(update.checkOutVerifiedReason, "ok");
});

test("check-out at radius+50 edge (140 m) is not flagged", () => {
  const before = {...checkIn(), verifiedFor: L.signature(L.checkInPosition(checkIn()), checkIn())};
  const after = {...before, checkOutTime: "ts", checkOutLocation: pos(0.00126)};
  assert.equal(apply(after, before).update.checkOutOutsideBranch, false);
});

test("a type == check_out record far away is flagged on create", () => {
  const out = {type: "check_out", delegateId: "d1", organizationId: "o1", branchId: "b1",
    location: pos(0.01), relatedCheckInId: "x"};
  const {update} = apply(out);
  assert.equal(update.checkOutOutsideBranch, true);
  assert.equal(update.verifiedInsideBranch, false);
});

test("no branchId / unknown branch / branch at 0,0 / no position -> reason, never flagged as inside", () => {
  assert.equal(apply(checkIn({branchId: undefined})).update.verifiedReason, "no_branch");
  assert.equal(apply(checkIn(), null, null).update.verifiedReason, "branch_not_found");
  assert.equal(apply(checkIn(), null, {location: {latitude: 0, longitude: 0}}).update.verifiedReason,
    "branch_without_location");
  const noPos = apply(checkIn({location: {latitude: 0, longitude: 0}})).update;
  assert.equal(noPos.verifiedReason, "no_position");
  assert.equal(noPos.verifiedInsideBranch, null);
});

test("a client cannot plant a verdict: create always recomputes and clears fake check-out fields", () => {
  const far = checkIn({location: pos(0.01)});
  const planted = {...far, verifiedInsideBranch: true, verifiedDistanceMeters: 1,
    verifiedFor: L.signature(L.checkInPosition(far), far),
    checkOutOutsideBranch: false, checkOutVerifiedFor: "x"};
  const {plan, update} = apply(planted);
  assert.equal(plan.checkIn, true);
  assert.equal(update.verifiedInsideBranch, false);
  assert.equal(plan.checkOut, true);
  assert.equal(update.checkOutOutsideBranch, null);
  assert.equal(update.checkOutVerifiedFor, null);
});

test("loop guard: the trigger's own write does not trigger a recompute", () => {
  const before = checkIn();
  const first = apply(before).update;
  const after = {...before, ...first, verifiedAt: "ts"};
  assert.deepEqual(L.planVerification(before, after), {checkIn: false, checkOut: false});

  const out = {...after, checkOutTime: "ts", checkOutLocation: pos(0.002)};
  const outUpdate = apply(out, after).update;
  const settled = {...out, ...outUpdate, checkOutVerifiedAt: "ts"};
  assert.deepEqual(L.planVerification(out, settled), {checkIn: false, checkOut: false});
});

test("staff moving the check-out location recomputes the check-out only", () => {
  const base = checkIn();
  const v = {...base, ...apply(base).update};
  const out = {...v, checkOutTime: "ts", checkOutLocation: pos(0.002)};
  const settled = {...out, ...apply(out, v).update};
  const moved = {...settled, checkOutLocation: pos(0.0001)};
  const {plan, update} = apply(moved, settled);
  assert.deepEqual(plan, {checkIn: false, checkOut: true});
  assert.equal(update.checkOutOutsideBranch, false);
});

test("legacy branch shapes: lat/lng and top-level latitude/longitude, default radius 100", () => {
  for (const b of [{location: {lat: 30.0444, lng: 31.2357}}, {latitude: 30.0444, longitude: 31.2357}]) {
    const u = apply(checkIn(), null, b).update;
    assert.equal(u.verifiedReason, "ok");
    assert.equal(u.verifiedBranchRadius, 100);
  }
});

test("delete is ignored", () => {
  assert.deepEqual(L.planVerification(checkIn(), null), {checkIn: false, checkOut: false});
});
