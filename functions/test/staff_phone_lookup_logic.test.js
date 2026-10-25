const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isStaffRole,
  publicStaffProfile,
  pickStaffProfile,
  staffRoleWeight,
} = require("../lib/staff_phone_lookup_logic");

test("staff lookup accepts canonical and legacy role spellings and rejects delegates", () => {
  assert.equal(isStaffRole("super-admin"), true);
  assert.equal(isStaffRole("super_admin"), true);
  assert.equal(isStaffRole("superadmin"), true);
  assert.equal(isStaffRole("company_hr"), true);
  assert.equal(isStaffRole("account_admin"), true);
  assert.equal(isStaffRole("technical-support"), true);
  assert.equal(isStaffRole("delegate"), false);
  assert.equal(isStaffRole(""), false);
  assert.ok(staffRoleWeight("super_admin") > staffRoleWeight("hr"));
});

test("public staff profile keeps email and org fields and drops non-staff", () => {
  const profile = publicStaffProfile("uid-1", {
    role: "super_admin",
    email: "omar@example.com",
    displayName: "Omar Fathalla",
    organizationUID: "org",
    companyUID: "comp",
    nationalityID: "secret",
  }, "01508899965");
  assert.equal(profile.uid, "uid-1");
  assert.equal(profile.email, "omar@example.com");
  assert.equal(profile.role, "super_admin");
  assert.equal(profile.phoneNumber, "01508899965");
  assert.equal(profile.organizationUID, "org");
  assert.equal(Object.prototype.hasOwnProperty.call(profile, "nationalityID"), false);
  assert.equal(publicStaffProfile("uid-2", {role: "delegate", email: "d@example.com"}, "010"), null);
  assert.equal(publicStaffProfile("uid-3", {role: "hr"}, "010"), null);
});

test("pickStaffProfile prefers the higher staff role", () => {
  const picked = pickStaffProfile([
    {uid: "hr", role: "hr", email: "hr@example.com"},
    {uid: "sa", role: "super-admin", email: "sa@example.com"},
  ]);
  assert.equal(picked.uid, "sa");
  assert.equal(pickStaffProfile([]), null);
});
