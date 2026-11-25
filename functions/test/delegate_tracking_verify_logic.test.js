// TAS-48: server verdict for delegate_tracking (pure logic, no emulator).
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/delegate_tracking_verify_logic");

// Fake branch in Cairo; 0.001 deg latitude ~= 111 m.
const BRANCH = {location: {latitude: 30.0444, longitude: 31.2357}, geofenceRadius: 100};
const MEMBER = {status: "active", fullName: "fake"};
const at = (dLatDeg, extra = {}) => ({
  lastLatitude: 30.0444 + dLatDeg, lastLongitude: 31.2357,
  branchId: "b1", organizationUID: "o1", companyUID: "c1", currentStatus: "inside", ...extra,
});
const verify = (doc, branch = BRANCH, membership = MEMBER) =>
  L.verifyTracking({inputs: L.trackingInputs(doc), branch, membership});

test("haversine matches a known distance", () => {
  const d = L.haversineMeters(30.0444, 31.2357, 30.0454, 31.2357);
  assert.ok(Math.abs(d - 111.2) < 0.5, `got ${d}`);
  assert.equal(L.haversineMeters(1, 2, 1, 2), 0);
});

test("honest inside: verified inside, no mismatch", () => {
  const v = verify(at(0.0005));
  assert.equal(v.verifiedStatus, "inside");
  assert.equal(v.statusMismatch, false);
  assert.equal(v.scopeMismatch, false);
  assert.equal(v.verifiedBranchRadius, 100);
  assert.equal(v.verifiedBranchLat, 30.0444);
  assert.ok(v.verifiedDistanceMeters > 50 && v.verifiedDistanceMeters < 60);
});

test("faked inside (branch coords = own position) far away: outside + mismatch", () => {
  const v = verify(at(0.01, {branchLat: 30.0544, branchLng: 31.2357, currentDistanceMeters: 0}));
  assert.equal(v.verifiedStatus, "outside");
  assert.equal(v.statusMismatch, true);
  assert.ok(v.verifiedDistanceMeters > 1000);
});

test("tolerance: radius + 50 is inside, the edge margin is not flagged", () => {
  // ~149 m: inside (limit = radius 100 + 50)
  assert.equal(verify(at(0.00134)).verifiedStatus, "inside");
  // ~167 m: outside, but within the 25 m margin, so an "inside" claim is not flagged
  const edge = verify(at(0.0015));
  assert.equal(edge.verifiedStatus, "outside");
  assert.equal(edge.statusMismatch, false);
  // ~200 m: flagged
  assert.equal(verify(at(0.0018)).statusMismatch, true);
});

test("client says outside while clearly inside is flagged too", () => {
  assert.equal(verify(at(0, {currentStatus: "outside"})).statusMismatch, true);
  assert.equal(verify(at(0.0018, {currentStatus: "outside"})).statusMismatch, false);
});

test("non-geofence client statuses are never a mismatch", () => {
  for (const s of ["offline", "checked_out", "forgot_signature", "suspended"]) {
    const v = verify(at(0.05, {currentStatus: s}));
    assert.equal(v.verifiedStatus, "outside");
    assert.equal(v.statusMismatch, false, s);
  }
});

test("unknown verdicts", () => {
  assert.equal(verify(at(0, {lastLatitude: null})).verifiedReason, "no_position");
  assert.equal(verify(at(0, {lastLatitude: 0, lastLongitude: 0})).verifiedReason, "no_position");
  assert.equal(verify(at(0, {branchId: ""})).verifiedReason, "no_branch");
  const noLoc = verify(at(0), {geofenceRadius: 100});
  assert.equal(noLoc.verifiedReason, "branch_without_location");
  assert.equal(noLoc.statusMismatch, false);
  for (const v of [noLoc, verify(at(0, {branchId: ""}))]) {
    assert.equal(v.verifiedStatus, "unknown");
    assert.equal(v.verifiedDistanceMeters, null);
  }
});

test("an unknown branch id cannot back an inside claim", () => {
  const v = verify(at(0), null);
  assert.equal(v.verifiedReason, "branch_not_found");
  assert.equal(v.verifiedStatus, "unknown");
  assert.equal(v.statusMismatch, true);
  assert.equal(verify(at(0, {currentStatus: "offline"}), null).statusMismatch, false);
});

test("branch geofence reads every shape the app reads", () => {
  assert.deepEqual(L.branchGeofence({location: {lat: 1, lng: 2}}), {lat: 1, lng: 2, radius: 100});
  assert.deepEqual(L.branchGeofence({latitude: 1, longitude: 2, geofenceRadius: 250}), {lat: 1, lng: 2, radius: 250});
  assert.deepEqual(L.branchGeofence({latitude: 1, longitude: 2, geofenceRadius: 0}).radius, 100);
  assert.equal(L.branchGeofence({location: {latitude: 0, longitude: 0}}), null);
  assert.equal(L.branchGeofence(null), null);
});

test("scope: missing, deleted or empty membership is a scope mismatch", () => {
  assert.equal(verify(at(0), BRANCH, null).scopeMismatch, true);
  assert.equal(verify(at(0), BRANCH, {status: "deleted"}).scopeMismatch, true);
  assert.equal(verify(at(0, {companyUID: "", companyId: ""})).scopeMismatch, true);
  // legacy companyId / organizationId fields are read too
  const legacy = at(0, {companyUID: undefined, organizationUID: undefined, companyId: "c1", organizationId: "o1"});
  assert.equal(L.trackingInputs(legacy).companyUID, "c1");
  assert.equal(verify(legacy).scopeMismatch, false);
});

test("loop guard: only input changes (or a missing verdict) trigger work", () => {
  const before = {...at(0), verifiedAt: 1, verifiedStatus: "inside"};
  assert.equal(L.needsVerification(null, at(0)), true, "create");
  assert.equal(L.needsVerification(before, null), false, "delete");
  // the trigger's own write: verified* only
  assert.equal(L.needsVerification(before, {...before, verifiedStatus: "outside", statusMismatch: true}), false);
  // battery / lastUpdated only
  assert.equal(L.needsVerification(before, {...before, batteryLevel: 40, lastUpdated: 5}), false);
  // client branch coords alone do not feed the server verdict
  assert.equal(L.needsVerification(before, {...before, branchLat: 1}), false);
  for (const [k, v] of [["lastLatitude", 31], ["lastLongitude", 30], ["branchId", "b2"],
    ["companyUID", "c2"], ["organizationUID", "o2"], ["currentStatus", "outside"]]) {
    assert.equal(L.needsVerification(before, {...before, [k]: v}), true, k);
  }
  // a client set() that dropped the verdict
  const {verifiedAt, ...dropped} = before; // eslint-disable-line no-unused-vars
  assert.equal(L.needsVerification(before, dropped), true);
});

test("server field list matches what verifyTracking writes", () => {
  const keys = [...Object.keys(verify(at(0))), "verifiedAt"].sort();
  assert.deepEqual(keys, [...L.TRACKING_SERVER_FIELDS].sort());
});
