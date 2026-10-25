const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isLegacySuperAdminRole,
  canonicalSuperAdminRole,
} = require("../scripts/migrate-super-admin-role");

test("legacy super_admin is the only role the migration rewrites", () => {
  assert.equal(isLegacySuperAdminRole("super_admin"), true);
  assert.equal(isLegacySuperAdminRole(" Super_Admin "), true);
  assert.equal(canonicalSuperAdminRole("super_admin"), "super-admin");
  assert.equal(canonicalSuperAdminRole("SUPER_ADMIN"), "super-admin");

  assert.equal(isLegacySuperAdminRole("super-admin"), false);
  assert.equal(isLegacySuperAdminRole("superadmin"), false);
  assert.equal(isLegacySuperAdminRole("superAdmin"), false);
  assert.equal(isLegacySuperAdminRole("delegate"), false);
  assert.equal(isLegacySuperAdminRole(null), false);
  assert.equal(canonicalSuperAdminRole("super-admin"), "super-admin");
  assert.equal(canonicalSuperAdminRole("delegate"), "delegate");
});
