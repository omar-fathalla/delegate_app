// TAS-23: staff callables take the caller's role and scope from token claims.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {claimBackedCaller, staffClaimsFor, staffClaimMissing} = require("../lib/staff_claims");
const {decideStaffCreate} = require("../lib/staff_accounts_logic");

const forgedAdmin = {role: "company-admin", organizationUID: "o1", companyUID: "c1", isActive: true, displayName: "x"};

test("a users doc role without a staff claim grants nothing", () => {
  for (const token of [{}, {role: "delegate"}, {role: ""}, null, undefined, {role: "promoter"}]) {
    const c = claimBackedCaller(forgedAdmin, token);
    assert.equal(c.role, "", JSON.stringify(token));
    assert.equal(c.organizationUID, undefined);
    assert.equal(c.companyUID, undefined);
    assert.equal(c.isActive, true);
    assert.equal(c.displayName, "x");
  }
  assert.equal(staffClaimMissing(forgedAdmin, {}), true);
  assert.equal(staffClaimMissing(forgedAdmin, {role: "company-admin"}), false);
});

test("forged super-admin doc is refused by createStaffUser logic", () => {
  const c = claimBackedCaller({role: "super-admin"}, {role: "delegate"});
  assert.equal(decideStaffCreate(c, {role: "hr", organizationUID: "o1", companyUID: "c1"}).ok, false);
});

test("role and scope come from the claims, never from the doc", () => {
  const c = claimBackedCaller(
    {role: "super-admin", organizationUID: "oX", companyUID: "cX", organizationUIDs: ["oX", "oY"]},
    {role: "company-admin", orgId: "o1", companyId: "c1"},
  );
  assert.equal(c.role, "company-admin");
  assert.equal(c.organizationUID, "o1");
  assert.equal(c.organizationId, "o1");
  assert.deepEqual(c.organizationUIDs, ["o1"]);
  assert.equal(c.companyUID, "c1");
  assert.equal(c.companyId, "c1");
});

test("organizationId claim (older createAdminUser shape) is accepted", () => {
  const c = claimBackedCaller({}, {role: "organization-admin", organizationId: "o2"});
  assert.equal(c.organizationUID, "o2");
  assert.equal(c.companyUID, "", "org-level role has no company scope");
});

test("missing scope claims fail closed for scoped roles", () => {
  const c = claimBackedCaller({role: "company-admin", organizationUID: "o1", companyUID: "c1"}, {role: "company-admin"});
  assert.equal(c.organizationUID, "");
  assert.equal(c.companyUID, "");
  assert.equal(decideStaffCreate(c, {role: "hr", organizationUID: "o1", companyUID: "c1"}).ok, false);
});

test("global roles carry no scope", () => {
  for (const role of ["super-admin", "technical_support", "accountant"]) {
    const c = claimBackedCaller({}, {role, orgId: "o1", companyId: "c1"});
    assert.equal(c.role, role);
    assert.equal(c.organizationUID, "");
    assert.equal(c.companyUID, "");
  }
});

test("delegate and field users keep their doc unchanged", () => {
  const doc = {role: "delegate", companyUID: "c1", organizationUID: "o1"};
  assert.deepEqual(claimBackedCaller(doc, {role: "delegate"}), doc);
  assert.deepEqual(claimBackedCaller(doc, {}), doc);
  assert.deepEqual(claimBackedCaller(undefined, {}), {});
});

test("staffClaimsFor builds the claim shape createStaffUser writes", () => {
  assert.deepEqual(staffClaimsFor("hr", "o1", "c1"), {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"});
  assert.deepEqual(staffClaimsFor("organization-admin", "o1", "c1"),
    {role: "organization-admin", orgId: "o1", organizationId: "o1", companyId: ""});
  assert.deepEqual(staffClaimsFor("technical_support", "o1", "c1"),
    {role: "technical_support", orgId: "", organizationId: "", companyId: ""});
  assert.equal(staffClaimsFor("delegate", "o1", "c1"), null);
  assert.equal(staffClaimsFor("", "o1", "c1"), null);
});

// Static guard: every staff callable that loads its caller from users/{uid}
// passes the doc through claimBackedCaller.
test("staff callables read the caller role through claimBackedCaller", () => {
  const files = [
    "check_delegate_duplicate.ts", "delegate_profile_edit.ts", "list_global_notify_staff.ts",
    "paymob_subscription.ts", "privileged_delegate_doc_reupload.ts", "send_staff_notification.ts",
    "set_delegate_hold.ts", "staff_accounts.ts", "start_billing_cycle.ts", "storage_upload_intent.ts",
    "supervisor_delegate_doc_reupload.ts", "task_proof_access.ts",
  ];
  for (const f of files) {
    const src = fs.readFileSync(path.join(__dirname, "..", "src", f), "utf8");
    assert.match(src, /claimBackedCaller\(/, f);
  }
  const staff = fs.readFileSync(path.join(__dirname, "..", "src", "staff_accounts.ts"), "utf8");
  assert.match(staff, /setCustomUserClaims\(user\.uid, \{\.\.\.claims\}\)/, "createStaffUser sets claims");
});
