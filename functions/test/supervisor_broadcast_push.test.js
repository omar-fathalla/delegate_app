// TAS-211: supervisor_<company> broadcasts are pushed to the company's
// supervisors and company admins. Pure logic + fake Firestore loader.
const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("../lib/supervisor_broadcast_push");

test("supervisorBroadcastCompany", () => {
  assert.equal(S.supervisorBroadcastCompany("supervisor_co1"), "co1");
  assert.equal(S.supervisorBroadcastCompany("supervisor_"), "");
  assert.equal(S.supervisorBroadcastCompany("company_co1"), "");
  assert.equal(S.supervisorBroadcastCompany("all"), "");
  assert.equal(S.supervisorBroadcastCompany(undefined), "");
});

test("company supervisor/admin roles only", () => {
  for (const r of ["supervisor", "company_supervisor", "company-admin", "company_admin", "admin"]) {
    assert.equal(S.isCompanySupervisorRole(r), true, r);
  }
  for (const r of ["delegate", "hr", "super-admin", "super_admin", "technical_support", "", null]) {
    assert.equal(S.isCompanySupervisorRole(r), false, String(r));
  }
});

test("recipients: unique, active, staff + supervisor delegates", () => {
  const uids = S.supervisorRecipientUids({
    staffUsers: [
      {uid: "a1", role: "company-admin"},
      {uid: "s1", role: "supervisor"},
      {uid: "h1", role: "hr"},
      {uid: "x1", role: "supervisor", status: "suspended"},
    ],
    supervisorDelegates: [{uid: "d-sup"}, {uid: "s1"}, {uid: "d-off", status: "rejected"}],
  });
  assert.deepEqual(uids.sort(), ["a1", "d-sup", "s1"]);
});

test("loadSupervisorSources reads users by company and the org path delegates", async () => {
  const calls = [];
  const snap = (docs) => ({docs: docs.map(([id, data]) => ({id, get: (k) => data[k]}))});
  const db = {
    collection: (path) => ({
      where: (f, op, v) => {
        calls.push([path, f, op, v]);
        if (path === "users" && f === "companyUID") return {get: async () => snap([["a1", {role: "admin"}]])};
        if (path === "users" && f === "companyId") return {get: async () => snap([["a1", {role: "admin"}], ["s1", {role: "supervisor"}]])};
        if (path.endsWith("/delegates")) return {get: async () => snap([["d1", {uid: "d1", position: "Supervisor"}]])};
        throw new Error("unexpected " + path);
      },
    }),
  };
  const src = await S.loadSupervisorSources(db, "co1", "org1");
  assert.deepEqual(src.staffUsers.map((u) => u.uid).sort(), ["a1", "s1"]);
  assert.deepEqual(src.supervisorDelegates.map((d) => d.uid), ["d1"]);
  assert.ok(calls.some(([p]) => p === "organizations/org1/companies/co1/delegates"));
});
