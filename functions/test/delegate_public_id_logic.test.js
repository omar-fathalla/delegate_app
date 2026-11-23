const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/delegate_public_id_logic");

const c = (org, data) => ({path: `organizations/${org}/companies/CO/delegates/u1`, data: {uid: "u1", fullName: "x", status: "active", ...data}});
const user = (data) => ({path: "users/u1", data});

test("canonical is the oldest (lowest) code", () => {
  assert.equal(L.canonicalPublicId(["DEL-6599", "DEL-6389", "bad", "", null, "DEL-6574"]), "DEL-6389");
  assert.equal(L.canonicalPublicId(["DEL-6458", "DEL-3396"]), "DEL-3396");
  assert.equal(L.canonicalPublicId([]), "");
});

test("several codes: every copy and users doc move to the oldest", () => {
  const p = L.planPublicId([c("A", {delegatePublicId: "DEL-6389"}), c("B", {delegatePublicId: "DEL-6595"}), c("C", {})],
    user({delegatePublicId: "DEL-6595"}));
  assert.equal(p.canonical, "DEL-6389");
  assert.equal(p.allocate, false);
  assert.deepEqual(p.paths.sort(), ["organizations/B/companies/CO/delegates/u1", "organizations/C/companies/CO/delegates/u1", "users/u1"].sort());
});

test("all equal: nothing to write (no loop)", () => {
  const p = L.planPublicId([c("A", {delegatePublicId: "DEL-1"}), c("B", {delegatePublicId: "DEL-1"})], user({delegatePublicId: "DEL-1"}));
  assert.deepEqual(p.paths, []);
});

test("code only on users doc is used for the copies", () => {
  const p = L.planPublicId([c("A", {}), c("B", {})], user({delegatePublicId: "DEL-50"}));
  assert.equal(p.canonical, "DEL-50");
  assert.equal(p.paths.length, 2);
});

test("no code anywhere: allocate only when active", () => {
  const a = L.planPublicId([c("A", {})], user({}));
  assert.equal(a.allocate, true);
  assert.deepEqual(a.paths.sort(), ["organizations/A/companies/CO/delegates/u1", "users/u1"].sort());
  const p = L.planPublicId([c("A", {status: "pending"})], null);
  assert.equal(p.allocate, false);
  assert.deepEqual(p.paths, []);
});

test("device-binding stubs are ignored", () => {
  const stub = {path: "organizations/F/companies/CO/delegates/u1", data: {boundDeviceId: "d"}};
  const p = L.planPublicId([c("A", {delegatePublicId: "DEL-7"}), stub], null);
  assert.deepEqual(p.paths, []);
  assert.equal(L.publicIdCheckNeeded(null, stub.data), false);
});

test("check needed: create, code change, becoming active; not other edits", () => {
  const a = {uid: "u1", status: "active", delegatePublicId: "DEL-1"};
  assert.equal(L.publicIdCheckNeeded(null, a), true);
  assert.equal(L.publicIdCheckNeeded(a, {...a, delegatePublicId: "DEL-2"}), true);
  assert.equal(L.publicIdCheckNeeded({...a, status: "pending"}, a), true);
  assert.equal(L.publicIdCheckNeeded(a, {...a, position: "Supervisor"}), false);
  assert.equal(L.publicIdCheckNeeded(a, null), false);
});

test("format keeps 4 digits minimum", () => {
  assert.equal(L.formatPublicId(7), "DEL-0007");
  assert.equal(L.formatPublicId(6898), "DEL-6898");
});

test("users doc: check when a code appears or changes only", () => {
  assert.equal(L.userPublicIdCheckNeeded(null, {delegatePublicId: "DEL-5"}), true);
  assert.equal(L.userPublicIdCheckNeeded({delegatePublicId: "DEL-4"}, {delegatePublicId: "DEL-5"}), true);
  assert.equal(L.userPublicIdCheckNeeded({delegatePublicId: "DEL-5"}, {delegatePublicId: "DEL-5", fullName: "x"}), false);
  assert.equal(L.userPublicIdCheckNeeded(null, {role: "admin"}), false);
  assert.equal(L.userPublicIdCheckNeeded({delegatePublicId: "DEL-5"}, null), false);
});
