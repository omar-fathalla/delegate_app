const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/staff_accounts_logic");

const T = (role, org = "o1", co = "c1") => ({role, organizationUID: org, companyUID: co});

test("super-admin creates any non-super staff role; never super-admin", () => {
  const sa = {role: "super-admin"};
  for (const r of ["organization-admin", "company-admin", "hr", "technical_support", "Supervisor"]) {
    assert.equal(L.decideStaffCreate(sa, T(r)).ok, true, r);
  }
  for (const r of ["super-admin", "super_admin", "superadmin"]) {
    assert.equal(L.decideStaffCreate(sa, T(r)).ok, false, r);
  }
});

test("staff-only: delegate/promoter/unknown roles are refused (delegates unchanged)", () => {
  for (const r of ["delegate", "promoter", "", "random"]) {
    assert.deepEqual(L.decideStaffCreate({role: "super-admin"}, T(r)), {ok: false, reason: "not_staff_role"});
  }
});

test("org-admin: own org only, no org-admin or tech support", () => {
  const oa = {role: "organization-admin", organizationUID: "o1"};
  assert.equal(L.decideStaffCreate(oa, T("company-admin")).ok, true);
  assert.equal(L.decideStaffCreate(oa, T("company-admin", "o2")).ok, false);
  assert.equal(L.decideStaffCreate(oa, T("organization-admin")).ok, false);
  assert.equal(L.decideStaffCreate(oa, T("technical-support")).ok, false);
});

test("company admin: own company, supervisor/HR only (rules companyCanGrant)", () => {
  const c = {role: "company-admin", organizationUID: "o1", companyUID: "c1"};
  for (const r of ["supervisor", "company_supervisor", "hr", "company-hr"]) assert.equal(L.decideStaffCreate(c, T(r)).ok, true, r);
  assert.equal(L.decideStaffCreate(c, T("hr", "o1", "c2")).reason, "out_of_scope");
  for (const r of ["company-admin", "marketing", "branches_marketing_manager", "accountant", "organization-admin"]) {
    assert.equal(L.decideStaffCreate(c, T(r)).ok, false, r);
  }
});

test("supervisor / HR: no staff role at all (field roles only, via the delegate flow)", () => {
  for (const role of ["Supervisor", "company_supervisor", "hr", "company-hr", "human_resources"]) {
    const c = {role, organizationUID: "o1", companyUID: "c1"};
    for (const r of ["marketing", "branches_marketing_manager", "accountant", "hr", "supervisor", "company-admin", "organization-admin"]) {
      assert.equal(L.decideStaffCreate(c, T(r)).ok, false, `${role}->${r}`);
    }
  }
});

test("company-admin target needs a company, even for super-admin / org-admin", () => {
  assert.equal(L.decideStaffCreate({role: "organization-admin", organizationUID: "o1"}, T("company-admin", "o1", "")).reason, "company_required");
  assert.equal(L.decideStaffCreate({role: "super-admin"}, T("company-admin", "o1", "")).reason, "company_required");
});

test("kill switch is off unless STAFF_CREATE_ENABLED is exactly true", () => {
  assert.equal(L.staffCreateEnabled({}), false);
  assert.equal(L.staffCreateEnabled({STAFF_CREATE_ENABLED: "1"}), false);
  assert.equal(L.staffCreateEnabled({STAFF_CREATE_ENABLED: "true"}), true);
});

test("inactive, missing or field callers are refused", () => {
  assert.equal(L.decideStaffCreate(null, T("hr")).ok, false);
  assert.equal(L.decideStaffCreate({role: "super-admin", isActive: false}, T("hr")).ok, false);
  assert.equal(L.decideStaffCreate({role: "delegate", organizationUID: "o1", companyUID: "c1"}, T("hr")).ok, false);
});

test("rate limit: 5 per hour per caller", () => {
  let s; const now = 1e12;
  for (let i = 0; i < 5; i++) { s = L.nextRate(s, now); assert.ok(s); }
  assert.equal(L.nextRate(s, now + 1000), null);
  assert.deepEqual(L.nextRate(s, now + L.SETUP_RATE_WINDOW_MS), {count: 1, windowStart: now + L.SETUP_RATE_WINDOW_MS});
});

test("claimInvite checks", () => {
  const inv = {email: "A@x.com", roleToAssign: "company-admin", organizationId: "o", companyId: "c", status: "pending"};
  const u = {email: "a@x.com", emailVerified: true};
  assert.deepEqual(L.decideClaim(inv, u, 1, 2), {ok: true});
  assert.equal(L.decideClaim(inv, {...u, emailVerified: false}, 1, 2).reason, "email_not_verified");
  assert.equal(L.decideClaim({...inv, status: "claimed"}, u, 1, 2).reason, "invite_not_pending");
  assert.equal(L.decideClaim(inv, u, 3, 2).reason, "invite_expired");
  assert.equal(L.decideClaim(inv, {...u, email: "b@x.com"}, 1, 2).reason, "email_mismatch");
  assert.equal(L.decideClaim({...inv, roleToAssign: "super-admin"}, u, 1, 2).reason, "role_not_allowed");
  assert.equal(L.decideClaim({...inv, companyId: ""}, u, 1, 2).reason, "invite_invalid");
  assert.equal(L.decideClaim(undefined, u, 1, 2).reason, "invite_not_found");
  assert.equal(L.decideClaim({...inv, claimedBy: "zz"}, u, 1, 2).reason, "invite_already_claimed");
  assert.equal(L.decideClaim({...inv, claimedByUid: "zz"}, u, 1, 2).reason, "invite_already_claimed");
  // the extra `role` key is ignored; only roleToAssign decides
  assert.deepEqual(L.decideClaim({...inv, role: "organization-admin"}, u, 1, 2), {ok: true});
  assert.equal(L.decideClaim({...inv, roleToAssign: "technical_support"}, u, 1, 2).reason, "role_not_allowed");
});

test("setup email escapes the name and never carries a password", () => {
  const m = L.setupEmail("<b>x</b>", "https://example.test/a?b=1&c=2");
  assert.ok(!m.html.includes("<b>x</b>"));
  assert.ok(m.html.includes("&amp;c=2"));
  assert.ok(!/password|كلمة السر المؤقتة/i.test(m.html));
});
