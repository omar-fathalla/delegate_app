// TAS-258: pushes go to every device of a user (fcm_tokens/{uid}/devices/*)
// plus the legacy fcm_tokens/{uid}.token, and a dead token is pruned only
// from the doc(s) that still hold it. In-memory Firestore, fake messaging.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {MemoryFirestore} = require("./helpers/memory_firestore");
const C = require("../lib/fcm_token_cleanup");
const alerts = require("../lib/paymob_superseded_alert");

const dead = Object.assign(new Error("gone"), {code: "messaging/registration-token-not-registered"});
const exists = async (db, p) => (await db.doc(p).get()).exists;

async function seed(db, docs) {
  for (const [p, data] of Object.entries(docs)) await db.doc(p).set(data);
}

test("tokensForUser: device docs + legacy, unique, with owning refs", async () => {
  const db = new MemoryFirestore();
  await seed(db, {
    "fcm_tokens/u1": {token: "tb"},
    "fcm_tokens/u1/devices/a": {token: "ta", platform: "android"},
    "fcm_tokens/u1/devices/b": {token: "tb", platform: "ios"},
    "fcm_tokens/u1/devices/empty": {token: ""},
    "fcm_tokens/u2/devices/x": {token: "tx"},
  });
  const t = await C.tokensForUser(db, "u1");
  assert.deepEqual(t.map((x) => x.token).sort(), ["ta", "tb"]);
  const tb = t.find((x) => x.token === "tb");
  assert.deepEqual(tb.refs.map((r) => r.path).sort(), ["fcm_tokens/u1", "fcm_tokens/u1/devices/b"]);
  assert.ok(t.every((x) => x.uid === "u1"));
});

test("tokensForUser: legacy only (old app) and nothing at all", async () => {
  const db = new MemoryFirestore();
  await seed(db, {"fcm_tokens/old": {token: "t-old"}});
  const t = await C.tokensForUser(db, "old");
  assert.deepEqual(t.map((x) => [x.token, x.refs.map((r) => r.path)]), [["t-old", ["fcm_tokens/old"]]]);
  assert.deepEqual(await C.tokensForUser(db, "nobody"), []);
  assert.deepEqual(await C.tokensForUser(db, ""), []);
});

test("tokensForUsers: one entry per token across users", async () => {
  const db = new MemoryFirestore();
  await seed(db, {
    "fcm_tokens/a/devices/d1": {token: "shared"},
    "fcm_tokens/b/devices/d1": {token: "shared"},
    "fcm_tokens/b/devices/d2": {token: "tb2"},
  });
  const t = await C.tokensForUsers(db, ["a", "b", "a"]);
  assert.deepEqual(t.map((x) => x.token).sort(), ["shared", "tb2"]);
});

test("dead device token: deletes the device doc, keeps legacy holding another token", async () => {
  const db = new MemoryFirestore();
  await seed(db, {
    "fcm_tokens/u1": {token: "tb"},
    "fcm_tokens/u1/devices/a": {token: "ta"},
    "fcm_tokens/u1/devices/b": {token: "tb"},
  });
  const targets = await C.tokensForUser(db, "u1");
  const n = await C.sendMulticastAndPrune(db, {
    sendEachForMulticast: async (m) => ({responses: m.tokens.map((tok) =>
      tok === "ta" ? {success: false, error: dead} : {success: true})}),
  }, targets, {notification: {title: "t", body: "b"}});
  assert.equal(n, 1);
  assert.equal(await exists(db, "fcm_tokens/u1/devices/a"), false);
  assert.equal(await exists(db, "fcm_tokens/u1/devices/b"), true);
  assert.equal(await exists(db, "fcm_tokens/u1"), true);
});

test("dead token held by device and legacy: both docs deleted", async () => {
  const db = new MemoryFirestore();
  await seed(db, {"fcm_tokens/u1": {token: "tb"}, "fcm_tokens/u1/devices/b": {token: "tb"}});
  const [t] = await C.tokensForUser(db, "u1");
  assert.equal(await C.pruneDeadToken(db, "u1", "tb", t.refs), true);
  assert.equal(await exists(db, "fcm_tokens/u1"), false);
  assert.equal(await exists(db, "fcm_tokens/u1/devices/b"), false);
});

test("a token rewritten meanwhile is not deleted", async () => {
  const db = new MemoryFirestore();
  await seed(db, {"fcm_tokens/u1": {token: "t1"}, "fcm_tokens/u1/devices/a": {token: "t1"}});
  const [t] = await C.tokensForUser(db, "u1");
  await db.doc("fcm_tokens/u1/devices/a").set({token: "t-new"});
  await db.doc("fcm_tokens/u1").set({token: "t-other"});
  assert.equal(await C.pruneDeadToken(db, "u1", "t1", t.refs), false);
  assert.equal((await db.doc("fcm_tokens/u1/devices/a").get()).get("token"), "t-new");
  assert.equal((await db.doc("fcm_tokens/u1").get()).get("token"), "t-other");
});

test("sendToUserTokens: one device uses send with the same payload + token", async () => {
  const db = new MemoryFirestore();
  await seed(db, {"fcm_tokens/u1": {token: "t1"}});
  const sent = [];
  const n = await C.sendToUserTokens(db, {
    send: async (m) => { sent.push(m); return "id"; },
    sendEachForMulticast: async () => { throw new Error("not expected"); },
  }, await C.tokensForUser(db, "u1"), {notification: {title: "T", body: "B"}, data: {type: "x"}});
  assert.equal(n, 1);
  assert.deepEqual(sent, [{notification: {title: "T", body: "B"}, data: {type: "x"}, token: "t1"}]);
});

test("sendToUserTokens: several devices use sendEachForMulticast", async () => {
  const db = new MemoryFirestore();
  await seed(db, {"fcm_tokens/u1": {token: "t1"}, "fcm_tokens/u1/devices/d2": {token: "t2"}});
  const calls = [];
  const n = await C.sendToUserTokens(db, {
    send: async () => { throw new Error("not expected"); },
    sendEachForMulticast: async (m) => { calls.push(m); return {responses: m.tokens.map(() => ({success: true}))}; },
  }, await C.tokensForUser(db, "u1"), {notification: {title: "T", body: "B"}});
  assert.equal(n, 2);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].tokens.sort(), ["t1", "t2"]);
  assert.deepEqual(calls[0].notification, {title: "T", body: "B"});
});

test("sendMulticastAndPrune chunks at 500 tokens", async () => {
  const db = new MemoryFirestore();
  const targets = Array.from({length: 1001}, (_, i) => ({uid: "u", token: `t${i}`, refs: []}));
  const sizes = [];
  const n = await C.sendMulticastAndPrune(db, {
    sendEachForMulticast: async (m) => { sizes.push(m.tokens.length); return {responses: m.tokens.map(() => ({success: true}))}; },
  }, targets, {data: {}});
  assert.deepEqual(sizes, [500, 500, 1]);
  assert.equal(n, 1001);
});

test("Paymob superseded alert reaches every device of a staff member", async () => {
  const db = new MemoryFirestore();
  await seed(db, {
    "users/sa1": {role: "super-admin"},
    "fcm_tokens/sa1": {token: "tok-legacy"},
    "fcm_tokens/sa1/devices/phone": {token: "tok-legacy"},
    "fcm_tokens/sa1/devices/tablet": {token: "tok-tablet"},
  });
  const multicasts = [];
  const res = await alerts.notifyPaymobSupersededPaymentRefund(db, {
    requestId: "ren1", attemptId: "a1", txId: "tx-258", amountCents: 100, currency: "EGP",
    companyUID: "co1", organizationUID: "org1", companyName: "fake",
    messaging: {
      send: async () => { throw new Error("not expected"); },
      sendEachForMulticast: async (m) => { multicasts.push(m); return {responses: m.tokens.map(() => ({success: true}))}; },
    },
  });
  assert.equal(res.fcmSent, 1);
  assert.deepEqual(multicasts[0].tokens.sort(), ["tok-legacy", "tok-tablet"]);
  assert.equal(multicasts[0].data.paymobTransactionId, "tx-258");
});

test("every send path reads tokens through tokensForUser (no direct fcm_tokens reads)", () => {
  const src = path.join(__dirname, "../src");
  for (const f of fs.readdirSync(src).filter((n) => n.endsWith(".ts") && n !== "fcm_token_cleanup.ts")) {
    const code = fs.readFileSync(path.join(src, f), "utf8");
    assert.doesNotMatch(code, /collection\(\s*["']fcm_tokens["']\s*\)/, `${f} reads fcm_tokens directly`);
  }
  const index = fs.readFileSync(path.join(src, "index.ts"), "utf8");
  const bodyOf = (fn) => {
    const start = index.indexOf(`export const ${fn}`);
    assert.ok(start >= 0, fn);
    const next = index.indexOf("export const ", start + 1);
    return index.slice(start, next < 0 ? undefined : next);
  };
  assert.match(bodyOf("onNotificationCreated"), /tokensForUsers?\(/, "onNotificationCreated uses tokensForUser");
  // TAS-34: the photo-permission triggers only write notification docs; the
  // push goes out once, from onNotificationCreated.
  for (const fn of ["onPhotoPermissionCreated", "onPhotoPermissionUpdated"]) {
    const body = bodyOf(fn);
    assert.doesNotMatch(body, /messaging\(\)|sendToUserTokens|sendMulticastAndPrune/, `${fn} must not push itself`);
    assert.match(body, /collection\("notifications"\)/, `${fn} writes a notification doc`);
  }
  const paymob = fs.readFileSync(path.join(src, "paymob_superseded_alert.ts"), "utf8");
  assert.match(paymob, /tokensForUser\(/);
});
