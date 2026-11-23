const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {
  callerScopeFrom,
  parseRequest,
  authorizeTarget,
  candidateFrom,
  candidateInScope,
  filterRecipients,
  phoneVariants,
  notificationDoc,
  recipientOrgCompany,
  senderRoleName,
  chunk,
  BATCH_SIZE,
} = require("../lib/send_staff_notification_logic");

const ORG = "org_dev_test";
const ORG2 = "org_dev_other";
const CO = "co_dev_test";
const CO2 = "co_dev_other";

const companyAdmin = {role: "company-admin", organizationUID: ORG, companyUID: CO};
const hr = {role: "hr", organizationUID: ORG, companyUID: CO};
const orgAdmin = {role: "organizationAdmin", organizationUID: ORG};
const superAdmin = {role: "super_admin"};
const techSupport = {role: "technicalSupport"};

function delegateDoc(id, org, co, extra = {}) {
  return candidateFrom(id, `organizations/${org}/companies/${co}/delegates/${id}`, {uid: id, ...extra});
}

describe("callerScopeFrom", () => {
  test("delegate token is rejected even with a staff users doc", () => {
    const r = callerScopeFrom(companyAdmin, "delegate");
    assert.equal(r.ok, false);
    assert.equal(r.reason, "delegate_not_allowed");
  });

  test("users doc with role delegate is rejected", () => {
    const r = callerScopeFrom({role: "delegate", companyUID: CO, organizationUID: ORG}, undefined);
    assert.equal(r.ok, false);
    assert.equal(r.code, "permission-denied");
  });

  test("missing profile is rejected", () => {
    assert.equal(callerScopeFrom(null, undefined).ok, false);
  });

  test("super admin and tech support are global", () => {
    assert.deepEqual(callerScopeFrom(superAdmin), {kind: "global"});
    assert.deepEqual(callerScopeFrom(techSupport), {kind: "global"});
    assert.deepEqual(callerScopeFrom({role: "super-admin"}), {kind: "global"});
  });

  test("org admin is org-scoped", () => {
    assert.deepEqual(callerScopeFrom(orgAdmin), {kind: "org", org: ORG});
  });

  test("company staff are company-scoped and need a company", () => {
    assert.deepEqual(callerScopeFrom(companyAdmin), {kind: "company", org: ORG, company: CO});
    assert.deepEqual(callerScopeFrom(hr), {kind: "company", org: ORG, company: CO});
    const r = callerScopeFrom({role: "hr", organizationUID: ORG});
    assert.equal(r.ok, false);
    assert.equal(r.reason, "no_scope");
  });

  test("scope comes from the users doc, not from claimed fields", () => {
    // The request body is never passed here; only the server-read doc is.
    const scope = callerScopeFrom({role: "admin", organizationUID: ORG, companyUID: CO});
    assert.equal(scope.company, CO);
  });

  test("marketing with a company is company-scoped, without one org-scoped", () => {
    assert.deepEqual(
      callerScopeFrom({role: "marketing_promotion", organizationUID: ORG, companyUID: CO}),
      {kind: "company", org: ORG, company: CO},
    );
    assert.deepEqual(callerScopeFrom({role: "marketing", organizationUID: ORG}), {kind: "org", org: ORG});
  });

  test("unknown role is rejected", () => {
    assert.equal(callerScopeFrom({role: "guest", organizationUID: ORG}).ok, false);
  });
});

describe("parseRequest", () => {
  const base = {title: "T", body: "B", type: "update"};

  test("valid all / org / role / user", () => {
    assert.equal(parseRequest({...base, target: {kind: "all"}}).ok, true);
    assert.deepEqual(parseRequest({...base, target: {kind: "org", organizationUID: ORG}}).target, {kind: "org", org: ORG});
    assert.deepEqual(parseRequest({...base, target: {kind: "role", role: "supervisor"}}).target, {kind: "role", role: "supervisor"});
  });

  test("missing text, bad type, bad role, bad target are invalid-argument", () => {
    assert.equal(parseRequest({title: "", body: "B", target: {kind: "all"}}).code, "invalid-argument");
    assert.equal(parseRequest({...base, type: "x", target: {kind: "all"}}).reason, "bad_type");
    assert.equal(parseRequest({...base, target: {kind: "role", role: "super_admin"}}).reason, "bad_role");
    assert.equal(parseRequest({...base, target: {kind: "nope"}}).reason, "bad_target");
    assert.equal(parseRequest({...base, target: {kind: "user"}}).reason, "missing_user");
  });

  test("user phone is normalised like staffPhoneLookup", () => {
    const r = parseRequest({...base, target: {kind: "user", phone: "+20 100 123 4567"}});
    assert.equal(r.target.phone, "01001234567");
    const ar = parseRequest({...base, target: {kind: "user", phone: "٠١٠٠١٢٣٤٥٦٧"}});
    assert.equal(ar.target.phone, "01001234567");
    assert.equal(parseRequest({...base, target: {kind: "user", phone: "12"}}).reason, "invalid_phone");
  });
});

describe("authorizeTarget", () => {
  const company = {kind: "company", org: ORG, company: CO};
  const org = {kind: "org", org: ORG};
  const global = {kind: "global"};

  test("'all' is a global broadcast only for global staff; scoped senders get their own scope", () => {
    assert.deepEqual(authorizeTarget(global, {kind: "all"}), {ok: true, target: {kind: "all"}});
    assert.deepEqual(authorizeTarget(org, {kind: "all"}), {ok: true, target: {kind: "org", org: ORG}});
    assert.deepEqual(authorizeTarget(company, {kind: "all"}),
      {ok: true, target: {kind: "company", org: ORG, company: CO}});
  });

  test("company staff cannot reach another company or the whole org", () => {
    assert.equal(authorizeTarget(company, {kind: "company", org: ORG, company: CO2}).reason, "out_of_scope");
    assert.equal(authorizeTarget(company, {kind: "company", org: ORG2, company: CO}).reason, "out_of_scope");
    assert.equal(authorizeTarget(company, {kind: "org", org: ORG}).reason, "out_of_scope");
    assert.deepEqual(
      authorizeTarget(company, {kind: "company", org: "", company: CO}),
      {ok: true, target: {kind: "company", org: ORG, company: CO}},
    );
  });

  test("org staff stays in its org", () => {
    assert.equal(authorizeTarget(org, {kind: "org", org: ORG2}).reason, "out_of_scope");
    assert.deepEqual(authorizeTarget(org, {kind: "org", org: ""}), {ok: true, target: {kind: "org", org: ORG}});
    assert.equal(authorizeTarget(org, {kind: "company", org: ORG2, company: CO2}).reason, "out_of_scope");
    assert.equal(authorizeTarget(org, {kind: "company", org: ORG, company: CO2}).ok, true);
  });

  test("global org target needs an org id", () => {
    assert.equal(authorizeTarget(global, {kind: "org", org: ""}).reason, "missing_org");
  });
});

describe("recipient scope filter", () => {
  test("delegate path gives org and company even without fields", () => {
    const c = delegateDoc("d1", ORG, CO);
    assert.deepEqual(c.orgIds, [ORG]);
    assert.deepEqual(c.companyIds, [CO]);
  });

  test("company scope drops another company's delegate and users", () => {
    const scope = {kind: "company", org: ORG, company: CO};
    const mine = delegateDoc("d1", ORG, CO);
    const other = delegateDoc("d2", ORG, CO2);
    const otherUser = candidateFrom("u3", "users/u3", {role: "admin", companyUID: CO2, organizationUID: ORG});
    assert.equal(candidateInScope(scope, mine), true);
    assert.equal(candidateInScope(scope, other), false);
    assert.deepEqual(filterRecipients(scope, [mine, other, otherUser]).map((c) => c.uid), ["d1"]);
  });

  test("org scope keeps every company in the org and drops other orgs", () => {
    const scope = {kind: "org", org: ORG};
    const a = delegateDoc("d1", ORG, CO);
    const b = delegateDoc("d2", ORG, CO2);
    const c = delegateDoc("d3", ORG2, "co_x");
    assert.deepEqual(filterRecipients(scope, [a, b, c]).map((x) => x.uid), ["d1", "d2"]);
  });

  test("multi-chain delegate is kept once, via the in-scope doc", () => {
    const scope = {kind: "company", org: ORG, company: CO};
    const outside = delegateDoc("d1", ORG2, CO2);
    const inside = delegateDoc("d1", ORG, CO);
    const r = filterRecipients(scope, [outside, inside]);
    assert.equal(r.length, 1);
    assert.deepEqual(r[0].companyIds, [CO]);
  });

  test("suspended, deleted and (for scoped callers) global staff are skipped", () => {
    const scope = {kind: "org", org: ORG};
    const s = delegateDoc("d1", ORG, CO, {status: "suspended"});
    const del = delegateDoc("d2", ORG, CO, {isDeleted: true});
    const sa = candidateFrom("u1", "users/u1", {role: "super_admin", organizationUID: ORG});
    assert.deepEqual(filterRecipients(scope, [s, del, sa]), []);
    assert.equal(filterRecipients({kind: "global"}, [sa]).length, 1);
  });
});

describe("helpers", () => {
  test("phoneVariants covers stored spellings", () => {
    const v = phoneVariants("+201001234567");
    for (const p of ["01001234567", "1001234567", "201001234567", "+201001234567"]) {
      assert.ok(v.includes(p), p);
    }
  });

  test("notification doc keeps the inbox shape", () => {
    const d = notificationDoc(
      {title: "T", body: "B", type: "update", senderUid: "s1", senderName: "N", senderRole: "admin", broadcastId: "b1"},
      "d1", ORG, CO, "01001234567",
    );
    assert.deepEqual(d, {
      delegateUid: "d1", organizationId: ORG, companyId: CO, title: "T", body: "B", type: "update",
      isRead: false, deletedBy: [], senderName: "N", senderRole: "admin", senderUid: "s1",
      createdBy: "s1", broadcastId: "b1", phoneNumber: "01001234567",
    });
  });

  test("company scope files recipients under the caller company", () => {
    const c = candidateFrom("u1", "users/u1", {companyUID: CO, organizationUID: ORG});
    assert.deepEqual(recipientOrgCompany({kind: "company", org: ORG, company: CO}, c), {organizationId: ORG, companyId: CO});
  });

  test("senderRole matches the Dart enum names", () => {
    assert.equal(senderRoleName("super_admin"), "superAdmin");
    assert.equal(senderRoleName("technical-support"), "technicalSupport");
    assert.equal(senderRoleName("organization_admin"), "organizationAdmin");
    assert.equal(senderRoleName("company-admin"), "admin");
    assert.equal(senderRoleName("branches_marketing"), "branchesMarketingManager");
    assert.equal(senderRoleName("marketing_promotion"), "marketingPromotion");
  });

  test("batches stay at or under 450", () => {
    const parts = chunk(Array.from({length: 1000}, (_, i) => i), BATCH_SIZE);
    assert.deepEqual(parts.map((p) => p.length), [450, 450, 100]);
  });
});
