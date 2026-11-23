// TAS-256: the server check (auditDelegateRequestOrgs) must accept the base
// (free) chain for a company that is not registered in it yet. Fake in-memory
// Firestore, no network.
const test = require("node:test");
const assert = require("node:assert/strict");
const {unavailableOrgsForRequest} = require("../lib/request_org_company_check");

function fakeDb(docs) {
  const snap = (path) => {
    const data = docs[path];
    return {exists: data !== undefined, get: (k) => (data || {})[k]};
  };
  return {
    doc: (path) => ({path, get: async () => snap(path)}),
    getAll: async (...refs) => refs.map((r) => snap(r.path)),
  };
}

test("base chain passes for a company not in it; other hidden chains do not", async () => {
  const db = fakeDb({
    "organizations/of": {name: "فتح الله (تجريبي)"},
    "organizations/oh": {name: "fathalla other"},
    "organizations/o1": {name: "كارفور"},
    "config/subscriptions": {freeChainOrgUids: ["of"]},
  });
  assert.deepEqual(await unavailableOrgsForRequest(db, "c-new", ["of"]), []);
  assert.deepEqual(await unavailableOrgsForRequest(db, "c-new", ["of", "oh", "o1", "gone"]), ["oh", "gone"]);
});

test("without the config the hidden base chain is refused as before", async () => {
  const db = fakeDb({"organizations/of": {name: "fathalla market"}});
  assert.deepEqual(await unavailableOrgsForRequest(db, "c-new", ["of"]), ["of"]);
});
