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
  assert.equal(staffRoleWeight("supervisor"), staffRoleWeight("admin"));
  assert.equal(staffRoleWeight("company_supervisor"), staffRoleWeight("company_admin"));
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

// TAS-24: per-IP window.
const {ipWindowNext, callerIp, IP_MAX_LOOKUPS, IP_WINDOW_MS} = require("../lib/staff_phone_lookup_logic");

test("ip window allows IP_MAX_LOOKUPS then blocks until the window ends", () => {
  let s = null;
  const t0 = 1_000_000;
  for (let i = 1; i <= IP_MAX_LOOKUPS; i++) {
    s = ipWindowNext(s, t0 + i);
    assert.equal(s.allowed, true, `lookup ${i}`);
  }
  const blocked = ipWindowNext(s, t0 + IP_MAX_LOOKUPS + 1);
  assert.equal(blocked.allowed, false);
  assert.ok(blocked.retryAfterSeconds > 0);
  const later = ipWindowNext(blocked, t0 + IP_WINDOW_MS + 5);
  assert.equal(later.allowed, true);
  assert.equal(later.count, 1);
});

test("callerIp takes the first forwarded hop, else the socket ip", () => {
  assert.equal(callerIp({"x-forwarded-for": "1.2.3.4, 10.0.0.1"}, "9.9.9.9"), "1.2.3.4");
  assert.equal(callerIp({}, "9.9.9.9"), "9.9.9.9");
  assert.equal(callerIp(undefined, undefined), "");
});

// TAS-314: a signed-out caller gets the email only.
const {lookupCallerOf, callerOwnsProfile, staffLookupResponse} = require("../lib/staff_phone_lookup_logic");

function fullProfile() {
  return publicStaffProfile("uid-1", {
    role: "organization_admin",
    email: "Owner@Example.com",
    displayName: "Owner",
    organizationUID: "org-1",
    organizationName: "Chain",
    companyUID: "co-1",
    companyName: "Company",
  }, "01500000001");
}

test("TAS-314: signed-out caller gets only the email", () => {
  const body = staffLookupResponse(fullProfile(), lookupCallerOf(undefined));
  assert.deepEqual(body, {email: "Owner@Example.com"});
  for (const key of ["uid", "role", "displayName", "organizationUID", "organizationName", "companyUID", "companyName", "phoneNumber"]) {
    assert.equal(Object.prototype.hasOwnProperty.call(body, key), false, key);
  }
});

test("TAS-314: anonymous and other signed-in callers get only the email", () => {
  const anon = lookupCallerOf({uid: "anon", token: {firebase: {sign_in_provider: "anonymous"}}});
  assert.equal(anon.anonymous, true);
  assert.deepEqual(staffLookupResponse(fullProfile(), anon), {email: "Owner@Example.com"});
  // Anonymous never owns, even with the same uid.
  const anonSameUid = lookupCallerOf({uid: "uid-1", token: {firebase: {sign_in_provider: "anonymous"}}});
  assert.equal(callerOwnsProfile(fullProfile(), anonSameUid), false);
  const other = lookupCallerOf({uid: "uid-9", token: {email: "other@example.com", firebase: {sign_in_provider: "password"}}});
  assert.deepEqual(staffLookupResponse(fullProfile(), other), {email: "Owner@Example.com"});
  const noEmail = lookupCallerOf({uid: "uid-9", token: {}});
  assert.equal(callerOwnsProfile(fullProfile(), noEmail), false);
});

test("TAS-314: the signed-in owner gets the full profile (by uid or by email)", () => {
  const byUid = lookupCallerOf({uid: "uid-1", token: {firebase: {sign_in_provider: "password"}}});
  assert.equal(staffLookupResponse(fullProfile(), byUid).role, "organization_admin");
  const byEmail = lookupCallerOf({uid: "auth-x", token: {email: " owner@example.COM ", firebase: {sign_in_provider: "password"}}});
  const body = staffLookupResponse(fullProfile(), byEmail);
  assert.equal(body.uid, "uid-1");
  assert.equal(body.organizationName, "Chain");
  assert.equal(body.companyUID, "co-1");
});

test("TAS-314: lookupCallerOf rejects malformed auth", () => {
  assert.equal(lookupCallerOf(null), null);
  assert.equal(lookupCallerOf({}), null);
  assert.equal(lookupCallerOf({uid: ""}), null);
  assert.deepEqual(lookupCallerOf({uid: "u"}), {uid: "u", email: "", anonymous: false});
});
