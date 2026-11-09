const test = require("node:test");
const assert = require("node:assert");
const t = require("../lib/password_setup_token_logic");

test("token is random, well-formed, and hash is stable hex", () => {
  const a = t.newSetupToken(), b = t.newSetupToken();
  assert.notStrictEqual(a, b);
  assert.ok(t.isWellFormedToken(a));
  assert.strictEqual(t.hashSetupToken(a), t.hashSetupToken(a));
  assert.match(t.hashSetupToken(a), /^[0-9a-f]{64}$/);
  assert.notStrictEqual(t.hashSetupToken(a), a);
});

test("malformed tokens rejected", () => {
  for (const x of [null, 5, "", "short", "a/b".repeat(20), "x".repeat(100)]) assert.ok(!t.isWellFormedToken(x));
});

test("token state", () => {
  const now = 1000;
  assert.strictEqual(t.tokenState(null, now), "missing");
  assert.strictEqual(t.tokenState({usedAtMs: 5, expiresAtMs: 9999}, now), "used");
  assert.strictEqual(t.tokenState({expiresAtMs: 999}, now), "expired");
  assert.strictEqual(t.tokenState({expiresAtMs: 1000}, now), "expired");
  assert.strictEqual(t.tokenState({}, now), "expired");
  assert.strictEqual(t.tokenState({expiresAtMs: 1001}, now), "ok");
  assert.strictEqual(t.SETUP_TOKEN_TTL_MS, 604800000);
});

test("setup link", () => {
  const l = new URL(t.buildSetupLink("https://tashil-account.web.app/auth/action/", "abc"));
  assert.strictEqual(l.host, "tashil-account.web.app");
  assert.strictEqual(l.searchParams.get("t"), "abc");
  assert.throws(() => t.buildSetupLink("http://evil.com/", "abc"));
});

test("password rules", () => {
  assert.strictEqual(t.passwordProblem("1234567"), "too_short");
  assert.strictEqual(t.passwordProblem(undefined), "invalid");
  assert.strictEqual(t.passwordProblem("x".repeat(129)), "too_long");
  assert.strictEqual(t.passwordProblem("Abcdefg1"), null);
});
