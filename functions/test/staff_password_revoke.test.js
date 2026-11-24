// TAS-40: a staff password set / reset ends every older session.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

test("completeStaffPasswordSetup revokes refresh tokens after changing the password", () => {
  const src = fs.readFileSync(path.join(__dirname, "../src/staff_password_email.ts"), "utf8");
  const start = src.indexOf("export const completeStaffPasswordSetup");
  assert.ok(start >= 0);
  const next = src.indexOf("\nexport const ", start + 1);
  const body = src.slice(start, next < 0 ? undefined : next);
  const update = body.indexOf("updateUser(claim.uid");
  const revoke = body.indexOf("revokeRefreshTokens(claim.uid)");
  assert.ok(update >= 0, "updates the password");
  assert.ok(revoke > update, "revokes sessions after the password change");
});
