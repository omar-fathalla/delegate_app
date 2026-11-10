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
