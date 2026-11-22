const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/company_chain_autolink_logic");

const FREE = "org_fathalla";
const cov = (o = {}) => ({
  free: false, periodCode: "2027_H1", covered: new Set(), inGrace: false,
  previousPeriodCode: "2026_H2", previousCovered: new Set(), freeChains: new Set([FREE]), ...o,
});
const chains = [
  {id: "A", name: "سلسلة أ"}, {id: "B", name: "سلسلة ب"}, {id: FREE, name: "فتح الله"},
];
const copy = (orgId, data) => ({orgId, data: {uid: "u1", organizationName: orgId, ...data}});

test("active + paid: linked to every company chain, free one included", () => {
  const p = L.planDelegate("u1", [copy("A", {status: "active"})], {status: "active"}, chains,
    cov({covered: new Set(["u1"])}));
  assert.deepEqual(p.create.sort(), ["B", FREE].sort());
  assert.equal(p.eligible, true);
});

test("active but unpaid: only the free chain", () => {
  const p = L.planDelegate("u1", [copy("A", {status: "active"})], null, chains, cov());
  assert.deepEqual(p.create, [FREE]);
  assert.equal(p.reason, "not_paid");
});

test("expired (paid copies suspended, free copy active): no paid chain", () => {
  const p = L.planDelegate("u1", [
    copy("A", {status: "suspended"}), copy(FREE, {status: "active"}),
  ], null, chains, cov());
  assert.deepEqual(p.create, []);
});

test("renewed: suspended copies back to active + coverage -> re-linked", () => {
  const p = L.planDelegate("u1", [
    copy("A", {status: "active"}), copy(FREE, {status: "active"}),
  ], null, chains, cov({covered: new Set(["u1"])}));
  assert.deepEqual(p.create, ["B"]);
});

test("activation alone never unlocks paid chains", () => {
  const p = L.planDelegate("u1", [copy("A", {status: "active", subscription: {periodCode: "2026_H2", paymentStatus: "paid"}})],
    null, chains, cov());
  assert.deepEqual(p.create, [FREE]);
});

test("subscription mirror for the current period counts as paid; waived only in free promotion", () => {
  const paid = [copy("A", {status: "active", subscription: {periodCode: "2027_H1", paymentStatus: "paid"}})];
  assert.equal(L.isCovered("u1", paid, cov()), true);
  const waived = [copy("A", {status: "active", subscription: {periodCode: "2027_H1", paymentStatus: "waived"}})];
  assert.equal(L.isCovered("u1", waived, cov()), false);
  assert.equal(L.isCovered("u1", waived, cov({free: true})), true);
});

test("grace keeps last period's coverage", () => {
  assert.equal(L.isCovered("u1", [], cov({inGrace: true, previousCovered: new Set(["u1"])})), true);
});

test("suspended login or no active copy: nothing", () => {
  assert.deepEqual(L.planDelegate("u1", [copy("A", {status: "active"})], {status: "suspended"}, chains,
    cov({free: true})).create, []);
  assert.deepEqual(L.planDelegate("u1", [copy("A", {status: "pending"})], null, chains, cov({free: true})).create, []);
});

test("free chains come from config and org flags", () => {
  const s = L.freeChainIds({freeChainOrgUids: ["x", " "]}, [{id: "y", data: {subscriptionExempt: true}}, {id: "z", data: {}}]);
  assert.deepEqual([...s].sort(), ["x", "y"]);
});

test("built copy: chain fields, plain position, autoLinked, no device binding", () => {
  const src = copy("A", {status: "active", fullName: "مندوب تجريبي", deviceBinding: {id: "d"}, originOrganizationName: "سلسلة أ"});
  const d = L.buildAutoLinkedCopy({source: src, chain: chains[1], allNames: ["سلسلة أ", "سلسلة ب", "فتح الله"]});
  assert.equal(d.organizationUID, "B");
  assert.equal(d.organizationName, "سلسلة ب");
  assert.equal(d.autoLinked, true);
  assert.equal(d.isExternal, true);
  assert.equal(d.deviceBinding, undefined);
  assert.equal(d.position, "Promoter");
});

test("plain position (TAS-234): role only, legacy chain suffix stripped, Supervisor kept", () => {
  assert.equal(L.plainPosition("Promoter"), "Promoter");
  assert.equal(L.plainPosition("Promoter (جملة ماركت + 9 سلاسل)"), "Promoter");
  assert.equal(L.plainPosition("Promoter (مشترك - 10 سلاسل)"), "Promoter");
  assert.equal(L.plainPosition("Supervisor (كارفور)"), "Supervisor");
  assert.equal(L.plainPosition("Supervisor"), "Supervisor");
  assert.equal(L.plainPosition(undefined), "Promoter");
  assert.equal(L.plainPosition(""), "Promoter");
  const sup = copy("A", {status: "active", position: "Supervisor (سلسلة أ)", originOrganizationName: "سلسلة أ"});
  assert.equal(L.buildAutoLinkedCopy({source: sup, chain: chains[1], allNames: ["سلسلة أ", "سلسلة ب"]}).position, "Supervisor");
});

test("delegate write filter: skips our own creates and plain field edits", () => {
  assert.equal(L.delegateWriteNeedsReconcile(null, {autoLinked: true}), false);
  assert.equal(L.delegateWriteNeedsReconcile(null, {status: "active"}), true);
  assert.equal(L.delegateWriteNeedsReconcile({status: "active"}, {status: "active", position: "x"}), false);
  assert.equal(L.delegateWriteNeedsReconcile({status: "suspended"}, {status: "active"}), true);
  assert.equal(L.delegateWriteNeedsReconcile({status: "active", subscription: {a: 1}}, {status: "active", subscription: {a: 2}}), true);
  assert.equal(L.delegateWriteNeedsReconcile({status: "active"}, null), false);
});

test("users mirror: free-chain delegates keep their login; only expiry suspensions are lifted", () => {
  assert.equal(L.mirrorUserStatusPlan({op: "suspend", user: {status: "active"}, hasActiveFreeChainCopy: true}), null);
  assert.deepEqual(L.mirrorUserStatusPlan({op: "suspend", user: {status: "active"}, hasActiveFreeChainCopy: false}),
    {status: "suspended", statusReason: "subscription_expired"});
  assert.deepEqual(L.mirrorUserStatusPlan({op: "reactivate", user: {status: "suspended", statusReason: "subscription_expired"}, hasActiveFreeChainCopy: false}),
    {status: "active", statusReason: null});
  assert.equal(L.mirrorUserStatusPlan({op: "reactivate", user: {status: "suspended", statusReason: "admin"}, hasActiveFreeChainCopy: false}), null);
});
