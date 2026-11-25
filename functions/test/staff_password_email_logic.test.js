const test = require("node:test");
const assert = require("node:assert");
const L = require("../lib/staff_password_email_logic");

function lookup({byUid = {}, byEmail = {}} = {}) {
  return {
    getRoleByUid: async (uid) => (Object.prototype.hasOwnProperty.call(byUid, uid) ? byUid[uid] : null),
    getRolesByEmail: async (email) => byEmail[email] || [],
  };
}

test("resolveCallerRole prefers users/{uid} and skips the email fallback", async () => {
  let emailed = 0;
  const role = await L.resolveCallerRole("u1", "admin@example.com", true, {
    getRoleByUid: async () => "supervisor",
    getRolesByEmail: async () => {
      emailed += 1;
      return ["super-admin"];
    },
  });
  assert.strictEqual(role, "supervisor");
  assert.strictEqual(emailed, 0);
});

test("email fallback requires email_verified; unverified token email is ignored", async () => {
  const db = lookup({byEmail: {"admin@example.com": ["super-admin"]}});
  const unverified = await L.resolveCallerRole("missing", "admin@example.com", false, db);
  assert.strictEqual(unverified, "");
  const noFlag = await L.resolveCallerRole("missing", "admin@example.com", undefined, db);
  assert.strictEqual(noFlag, "");
  const verified = await L.resolveCallerRole("missing", "admin@example.com", true, db);
  assert.strictEqual(verified, "super-admin");
});

test("verified email fallback prefers a role that can send staff invites", async () => {
  const role = await L.resolveCallerRole("missing", "staff@example.com", true, lookup({
    byEmail: {"staff@example.com": ["delegate", "super-admin"]},
  }));
  assert.strictEqual(role, "super-admin");
});

test("STAFF_CREATE_ENABLED kill switch is off unless exactly true", () => {
  assert.strictEqual(L.staffCreateAllowed({}), false);
  assert.strictEqual(L.staffCreateAllowed({STAFF_CREATE_ENABLED: "1"}), false);
  assert.strictEqual(L.staffCreateAllowed({STAFF_CREATE_ENABLED: "TRUE"}), false);
  assert.strictEqual(L.staffCreateAllowed({STAFF_CREATE_ENABLED: "true"}), true);
});

// TAS-317: password email limits.
const {ipWindowNext} = require("../lib/staff_phone_lookup_logic");

test("TAS-317: limit keys are hashed, case-insensitive and kind-scoped", () => {
  const a = L.passwordEmailLimitKey("email", " Staff@Example.com ");
  const b = L.passwordEmailLimitKey("email", "staff@example.com");
  assert.strictEqual(a, b);
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.ok(!a.includes("staff"));
  assert.notStrictEqual(L.passwordEmailLimitKey("ip", "1.2.3.4"), L.passwordEmailLimitKey("caller", "1.2.3.4"));
  assert.strictEqual(L.passwordEmailLimitKey("ip", ""), "");
  assert.strictEqual(L.passwordEmailLimitKey("ip", undefined), "");
});

test("TAS-317: limits are 3 per target, 10 per IP, 30 per admin, per hour", () => {
  assert.strictEqual(L.PASSWORD_EMAIL_WINDOW_MS, 60 * 60 * 1000);
  assert.strictEqual(L.PASSWORD_EMAIL_MAX_PER_TARGET, 3);
  assert.strictEqual(L.PASSWORD_RESET_MAX_PER_IP, 10);
  assert.strictEqual(L.PASSWORD_SETUP_MAX_PER_CALLER, 30);
  assert.strictEqual(L.PASSWORD_EMAIL_LIMIT_COLLECTION, "staff_password_email_limits");
});

function run(max, times, start = 1_000_000, step = 1000) {
  let state = null;
  const out = [];
  for (let i = 0; i < times; i++) {
    const n = ipWindowNext(state, start + i * step, L.PASSWORD_EMAIL_WINDOW_MS, max);
    out.push(n);
    state = {count: n.count, windowStartMs: n.windowStartMs};
  }
  return out;
}

test("TAS-317: the 4th email to the same target in an hour is refused", () => {
  const r = run(L.PASSWORD_EMAIL_MAX_PER_TARGET, 4);
  assert.deepStrictEqual(r.map((x) => x.allowed), [true, true, true, false]);
  assert.ok(r[3].retryAfterSeconds > 0 && r[3].retryAfterSeconds <= 3600);
});

test("TAS-317: the 11th reset from one IP in an hour is refused, and the window resets", () => {
  const r = run(L.PASSWORD_RESET_MAX_PER_IP, 11);
  assert.strictEqual(r.filter((x) => x.allowed).length, 10);
  assert.strictEqual(r[10].allowed, false);
  const after = ipWindowNext({count: r[10].count, windowStartMs: r[10].windowStartMs},
    r[10].windowStartMs + L.PASSWORD_EMAIL_WINDOW_MS, L.PASSWORD_EMAIL_WINDOW_MS, L.PASSWORD_RESET_MAX_PER_IP);
  assert.strictEqual(after.allowed, true);
  assert.strictEqual(after.count, 1);
});
