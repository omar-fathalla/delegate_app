// TAS-303: delegate claims are stored on the Auth user, also on first login.
const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {storeDelegateClaims} = require("../lib/ensure_auth_user");

function fakeAuth({exists = false, raceOnCreate = false} = {}) {
  const calls = [];
  return {
    calls,
    async getUser(uid) { calls.push(["get", uid]); if (!exists) throw {code: "auth/user-not-found"}; return {uid}; },
    async createUser(p) { calls.push(["create", p.uid]); if (raceOnCreate) throw {code: "auth/uid-already-exists"}; exists = true; },
    async setCustomUserClaims(uid, c) { calls.push(["claims", uid, c.role]); },
  };
}

describe("storeDelegateClaims", () => {
  test("first login: creates the user, then stores the claims", async () => {
    const a = fakeAuth();
    assert.equal(await storeDelegateClaims(a, "d1", {role: "delegate"}), "created_and_stored");
    assert.deepEqual(a.calls, [["get", "d1"], ["create", "d1"], ["claims", "d1", "delegate"]]);
  });
  test("existing user: only stores the claims", async () => {
    const a = fakeAuth({exists: true});
    assert.equal(await storeDelegateClaims(a, "d1", {role: "delegate"}), "stored");
    assert.deepEqual(a.calls.map((c) => c[0]), ["get", "claims"]);
  });
  test("a parallel login created it first: still stores the claims", async () => {
    const a = fakeAuth({raceOnCreate: true});
    assert.equal(await storeDelegateClaims(a, "d1", {role: "delegate"}), "stored");
    assert.deepEqual(a.calls.map((c) => c[0]), ["get", "create", "claims"]);
  });
  test("other errors are not swallowed", async () => {
    const a = fakeAuth();
    a.getUser = async () => { throw {code: "auth/internal-error"}; };
    await assert.rejects(storeDelegateClaims(a, "d1", {role: "delegate"}));
  });
});
