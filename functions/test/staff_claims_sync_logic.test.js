/**
 * TAS-23: canonical staff roles, the sync trigger plan and the backfill plan.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/staff_claims_sync_logic");
const {staffClaimsFor} = require("../lib/staff_claims");

test("every staff spelling maps to one canonical claim role", () => {
  const cases = {
    "super-admin": ["super-admin", "super_admin", "superAdmin", "SUPER_ADMIN", " Super-Admin "],
    "technical_support": ["technical_support", "technical-support", "technicalSupport", "tech_support", "techsupport"],
    "accountant": ["accountant", "accounting", "account_admin"],
    "organization-admin": ["organization-admin", "organization_admin", "organizationAdmin", "org-admin"],
    "company-admin": ["company-admin", "company_admin", "companyadmin", "admin"],
    "supervisor": ["supervisor", "company_supervisor", "company-supervisor"],
    "hr": ["hr", "company-hr", "company_hr", "human_resources"],
    "marketing": ["marketing"],
    "marketing_promotion": ["marketing_promotion", "marketingPromotion", "marketingpromotion"],
    "branches_marketing": ["branches_marketing", "branches-marketing", "branches_marketing_manager",
      "branches-marketing-manager", "branchesMarketingManager"],
  };
  for (const [canon, spellings] of Object.entries(cases)) {
    for (const s of spellings) assert.equal(L.canonicalStaffRole(s), canon, s);
  }
  for (const s of ["delegate", "promoter", "", null, 3, "manager"]) assert.equal(L.canonicalStaffRole(s), "");
});

test("claims per scope: global none, org without company, company required", () => {
  assert.deepEqual(L.claimsForRole("accountant", "o1", "c1").claims, {role: "accountant", orgId: "", organizationId: "", companyId: ""});
  assert.deepEqual(L.claimsForRole("org-admin", "o1", "c1").claims, {role: "organization-admin", orgId: "o1", organizationId: "o1", companyId: ""});
  assert.deepEqual(L.claimsForRole("admin", "o1", "c1").claims, {role: "company-admin", orgId: "o1", organizationId: "o1", companyId: "c1"});
  assert.equal(L.claimsForRole("hr", "o1", "").claims, null);
  assert.equal(L.claimsForRole("hr", "", "c1").reason, "no organization on users doc");
  assert.deepEqual(L.claimsForRole("branchesMarketingManager", "o1", "").claims,
    {role: "branches_marketing", orgId: "o1", organizationId: "o1", companyId: ""});
  assert.deepEqual(L.desiredFromDoc({role: "hr", organizationId: "o1", companyId: "c1"}).claims,
    {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"});
});

test("createStaffUser writes the canonical spelling", () => {
  assert.deepEqual(staffClaimsFor("admin", "o1", "c1"), {role: "company-admin", orgId: "o1", organizationId: "o1", companyId: "c1"});
  assert.deepEqual(staffClaimsFor("company_hr", "o1", "c1"), {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"});
});

test("merge keeps other claim keys; strip removes only staff keys", () => {
  const want = {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"};
  assert.deepEqual(L.mergeStaffClaims({mfaGraceUntil: 5, role: "x"}, want), {mfaGraceUntil: 5, ...want});
  assert.deepEqual(L.stripStaffClaims({mfaGraceUntil: 5, ...want}), {mfaGraceUntil: 5});
});

test("membership paths and confirmation", () => {
  const co = {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"};
  assert.deepEqual(L.membershipPaths("u", co), ["organizations/o1/companies/c1/members/u"]);
  const oa = {role: "organization-admin", orgId: "o1", organizationId: "o1", companyId: ""};
  assert.deepEqual(L.membershipPaths("u", oa), ["organizations/o1/members/u"]);
  const mk = {role: "marketing", orgId: "o1", organizationId: "o1", companyId: "c1"};
  assert.deepEqual(L.membershipPaths("u", mk), ["organizations/o1/companies/c1/members/u", "organizations/o1/members/u"]);
  assert.deepEqual(L.membershipPaths("u", {role: "accountant", orgId: "", organizationId: "", companyId: ""}), []);
  assert.equal(L.membershipConfirms({role: "company-admin", status: "active"}, co), true);
  assert.equal(L.membershipConfirms({status: "removed"}, co), false);
  assert.equal(L.membershipConfirms(null, co), false);
  assert.equal(L.membershipConfirms({role: "company-admin"}, oa), false, "org admin needs an org-admin membership");
  assert.equal(L.membershipConfirms({role: "org-admin", status: "active"}, oa), true);
});

test("sync plan: unrelated edits and spelling-only changes do nothing", () => {
  const hr = {role: "hr", organizationUID: "o1", companyUID: "c1", displayName: "a"};
  const claims = {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"};
  assert.equal(L.planStaffClaimSync(hr, {...hr, displayName: "b"}, claims).action, "noop");
  assert.equal(L.planStaffClaimSync(hr, {...hr, role: "company_hr"}, claims).action, "noop");
  assert.equal(L.planStaffClaimSync(hr, {...hr, isActive: false}, {}).action, "noop");
});

test("sync plan: removals revoke, upgrades need membership, global never granted", () => {
  const hr = {role: "hr", organizationUID: "o1", companyUID: "c1"};
  const claims = {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"};
  assert.equal(L.planStaffClaimSync(hr, null, claims).action, "revoke");
  assert.equal(L.planStaffClaimSync(hr, {...hr, role: "delegate"}, claims).action, "revoke");
  assert.equal(L.planStaffClaimSync(hr, {...hr, companyUID: ""}, claims).action, "revoke");
  assert.equal(L.planStaffClaimSync(hr, {...hr, role: "accountant"}, claims).action, "revoke");
  assert.equal(L.planStaffClaimSync(hr, {...hr, role: "accountant"}, {}).action, "noop");
  const up = L.planStaffClaimSync(hr, {...hr, role: "company-admin"}, claims);
  assert.equal(up.action, "grant");
  assert.deepEqual(up.want, {role: "company-admin", orgId: "o1", organizationId: "o1", companyId: "c1"});
  const move = L.planStaffClaimSync(hr, {...hr, companyUID: "c2"}, claims);
  assert.equal(move.action, "grant");
  assert.equal(move.want.companyId, "c2");
  // A forged self-promotion on a fresh doc is only a "grant" candidate: it still needs membership.
  assert.equal(L.planStaffClaimSync(null, {role: "company-admin", organizationUID: "o1", companyUID: "c1"}, {}).action, "grant");
});

test("sync plan: super-admin, technical support and delegate claims are never touched", () => {
  const sa = {role: "super-admin"};
  assert.equal(L.planStaffClaimSync(sa, {role: "hr", organizationUID: "o1", companyUID: "c1"}, {role: "super-admin"}).action, "noop");
  assert.equal(L.planStaffClaimSync(sa, null, {role: "technical_support"}).action, "noop");
  assert.equal(L.planStaffClaimSync({role: "delegate"}, {role: "hr", organizationUID: "o1", companyUID: "c1"},
    {role: "delegate", delegateId: "d"}).action, "noop");
});

test("backfill plan covers every staff role", () => {
  const base = {authExists: true, authDisabled: false, members: [], allowListed: false};
  const p = (doc, extra = {}) => L.planBackfill({...base, doc, claims: {}, ...extra});
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c1"}).action, "manual");
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c1"}, {members: [{status: "active"}]}).action, "set");
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c1"}, {allowListed: true}).action, "set");
  assert.equal(p({role: "accountant"}).action, "manual");
  assert.equal(p({role: "accountant"}, {allowListed: true}).action, "set");
  assert.equal(p({role: "super-admin"}, {claims: {role: "super-admin"}}).action, "ok");
  assert.equal(p({role: "organization-admin", organizationUID: "o1"},
    {claims: {role: "organization-admin", organizationId: "o1"}}).action, "set", "adds orgId next to organizationId");
  assert.equal(p({role: "organization-admin", organizationUID: "o1"},
    {claims: {role: "organization-admin", orgId: "o1", organizationId: "o1", companyId: ""}}).action, "ok");
  assert.equal(p({role: "marketing", organizationUID: "o1"}, {members: [{role: "marketing"}]}).action, "set");
  assert.equal(p({role: "hr", organizationUID: "o1"}).reason, "no company on users doc");
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c1"}, {claims: {role: "delegate"}, allowListed: true}).action, "manual");
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c1"}, {authExists: false}).action, "skip");
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c1"}, {authDisabled: true}).action, "skip");
  assert.equal(p({role: "delegate"}).action, "skip");
  // Same role claim, but the doc moved to another company: needs proof.
  assert.equal(p({role: "hr", organizationUID: "o1", companyUID: "c2"},
    {claims: {role: "hr", orgId: "o1", organizationId: "o1", companyId: "c1"}}).action, "manual");
});

test("the sync trigger is exported and documented with its deploy name", () => {
  const src = require("fs").readFileSync(require("path").join(__dirname, "../src/index.ts"), "utf8");
  assert.match(src, /export \{syncStaffClaimsOnUserWrite\} from "\.\/staff_claims_sync"/);
});
