// TAS-372: printed branch QR signed by the server, and the integrity mark.
const test = require("node:test");
const assert = require("node:assert/strict");
const Q = require("../lib/attendance_qr_logic");

const KEY = "test-only-key-not-a-secret";
const signed = (over = {}) => {
  const p = Q.buildQrPayload({key: KEY, organizationUID: "o1", branchId: "b1", branchName: "Fake Alpha",
    qrVersion: 2});
  return {...p, ...over};
};
const decide = (qr, over = {}) => Q.decideQr({proof: Q.parseQrProof(qr), branchId: "b1",
  branchOrganizationUID: "o1", branch: {qrVersion: 2}, key: KEY, legacyMode: "accept", ...over});

test("payload keeps the fields old app versions read", () => {
  const p = signed();
  assert.equal(p.type, "attendance");
  assert.equal(p.branch, "Fake Alpha");
  assert.equal(p.branchId, "b1");
  assert.equal(p.organizationUID, "o1");
  assert.equal(p.v, 2);
  assert.equal(p.qrVersion, 2);
  assert.match(p.sig, /^[A-Za-z0-9_-]{43}$/);
});

test("valid signed QR of the current version is accepted", () => {
  assert.deepEqual(decide(signed()), {ok: true, qrCheck: "signed", qrVersion: 2});
});

test("wrong signature, another branch or chain is qr_invalid", () => {
  assert.equal(decide(signed({sig: signed().sig.replace(/^./, (c) => (c === "A" ? "B" : "A"))})).reason,
    "qr_invalid");
  assert.equal(decide(signed(), {branchId: "b2"}).reason, "qr_invalid");
  assert.equal(decide(signed(), {branchOrganizationUID: "o2"}).reason, "qr_invalid");
  assert.equal(decide(signed(), {key: "other-key"}).reason, "qr_invalid");
  assert.equal(decide(signed(), {key: ""}).reason, "qr_invalid");
  assert.equal(decide(signed({qrVersion: 0})).reason, "qr_invalid");
});

test("an older version (after regenerate) is qr_old", () => {
  assert.equal(decide(signed(), {branch: {qrVersion: 3}}).reason, "qr_old");
  assert.match(decide(signed(), {branch: {qrVersion: 3}}).message, /قديم/);
});

test("legacy QR: accepted and marked, unless the branch has a signed QR or mode is reject", () => {
  assert.deepEqual(decide({legacy: true}, {branch: {}}), {ok: true, qrCheck: "legacy"});
  assert.equal(decide({legacy: true}).reason, "qr_old");
  assert.equal(decide({legacy: true}, {branch: {}, legacyMode: "reject"}).reason, "qr_old");
});

test("no QR (geofence mode) is marked none", () => {
  assert.deepEqual(decide(undefined), {ok: true, qrCheck: "none"});
  assert.deepEqual(decide({}), {ok: true, qrCheck: "none"});
});

test("branchQrVersion ignores bad values", () => {
  assert.equal(Q.branchQrVersion({qrVersion: 4}), 4);
  assert.equal(Q.branchQrVersion({qrVersion: "4"}), 0);
  assert.equal(Q.branchQrVersion({qrVersion: -1}), 0);
  assert.equal(Q.branchQrVersion(null), 0);
});

test("device integrity from the App Check token", () => {
  assert.equal(Q.deviceIntegrityOf(undefined), "missing");
  assert.equal(Q.deviceIntegrityOf({appId: "x"}), "verified");
  assert.equal(Q.deviceIntegrityOf({appId: "x", alreadyConsumed: true}), "replayed");
});

test("who may print or regenerate a branch QR", () => {
  assert.equal(Q.mayManageBranchQr({}, "super-admin", "o1"), true);
  assert.equal(Q.mayManageBranchQr({}, "technical_support", "o1"), true);
  assert.equal(Q.mayManageBranchQr({orgId: "o1"}, "organization-admin", "o1"), true);
  assert.equal(Q.mayManageBranchQr({orgId: "o2"}, "organization-admin", "o1"), false);
  assert.equal(Q.mayManageBranchQr({orgId: "o1"}, "hr", "o1"), false);
  assert.equal(Q.mayManageBranchQr({orgId: "o1"}, "", "o1"), false);
});
