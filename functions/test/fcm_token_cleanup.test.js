// TAS-80: dead FCM tokens are pruned from fcm_tokens/{uid}, only when the doc
// still holds that token. Fake Firestore/messaging, no network.
const test = require("node:test");
const assert = require("node:assert/strict");
const C = require("../lib/fcm_token_cleanup");

function fakeDb(docs) {
  const ref = (id) => ({id});
  return {
    docs,
    collection: () => ({doc: (id) => ref(id)}),
    runTransaction: async (fn) => fn({
      get: async (r) => ({exists: r.id in docs, get: (k) => (docs[r.id] || {})[k]}),
      delete: (r) => { delete docs[r.id]; },
    }),
  };
}
const dead = Object.assign(new Error("gone"), {code: "messaging/registration-token-not-registered"});

test("isDeadTokenError only for dead-token codes", () => {
  assert.equal(C.isDeadTokenError(dead), true);
  assert.equal(C.isDeadTokenError({code: "messaging/invalid-registration-token"}), true);
  assert.equal(C.isDeadTokenError({code: "messaging/internal-error"}), false);
  assert.equal(C.isDeadTokenError(null), false);
});

test("sendToUserToken prunes a dead token and returns false", async () => {
  const db = fakeDb({u1: {token: "t1"}});
  const ok = await C.sendToUserToken(db, {send: async () => { throw dead; }}, "u1", {token: "t1"});
  assert.equal(ok, false);
  assert.equal("u1" in db.docs, false);
});

test("a newer token written meanwhile is kept", async () => {
  const db = fakeDb({u1: {token: "t-new"}});
  await C.sendToUserToken(db, {send: async () => { throw dead; }}, "u1", {token: "t-old"});
  assert.deepEqual(db.docs.u1, {token: "t-new"});
});

test("other errors are rethrown and nothing is deleted", async () => {
  const db = fakeDb({u1: {token: "t1"}});
  await assert.rejects(C.sendToUserToken(db, {send: async () => { throw {code: "messaging/internal-error"}; }}, "u1", {token: "t1"}));
  assert.ok("u1" in db.docs);
});

test("multicast prunes only the dead recipients", async () => {
  const db = fakeDb({a: {token: "ta"}, b: {token: "tb"}, c: {token: "tc"}});
  const n = await C.pruneDeadFromMulticast(db,
    [{uid: "a", token: "ta"}, {uid: "b", token: "tb"}, {uid: "c", token: "tc"}],
    {responses: [{success: true}, {success: false, error: dead}, {success: false, error: {code: "messaging/unavailable"}}]});
  assert.equal(n, 1);
  assert.deepEqual(Object.keys(db.docs).sort(), ["a", "c"]);
});
