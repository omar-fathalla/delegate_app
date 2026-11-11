const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/request_org_company");

test("requestOrganizationIds includes every list entry and the primary, unique, capped at 10", () => {
  const ids = L.requestOrganizationIds({
    organizationUID: "o1",
    organizationUIDs: ["o1", "o2", "o2", "", "o3"],
  });
  assert.deepEqual(ids, ["o1", "o2", "o3"]);
});

test("summarizeOrgCompanyCheck fails closed without a company and when a chain is missing", () => {
  const missing = L.summarizeOrgCompanyCheck({
    companyUID: "c1", orgIds: ["o1", "o9"], missing: ["o9"],
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "org_not_in_company");
  assert.deepEqual(missing.missing, ["o9"]);
  const noCo = L.summarizeOrgCompanyCheck({companyUID: "", orgIds: ["o1"], missing: ["o1"]});
  assert.equal(noCo.ok, false);
  assert.equal(noCo.reason, "missing_company");
  const ok = L.summarizeOrgCompanyCheck({companyUID: "c1", orgIds: ["o1", "o2"], missing: []});
  assert.equal(ok.ok, true);
  assert.equal(ok.reason, "ok");
});

test("requestApprovalOrgCheckOk requires the ok mark for new_delegate and add_organization", () => {
  assert.equal(L.requestApprovalOrgCheckOk({requestType: "new_delegate", orgCompanyCheck: "ok"}), true);
  assert.equal(L.requestApprovalOrgCheckOk({requestType: "add_organization", orgCompanyCheck: "ok"}), true);
  assert.equal(L.requestApprovalOrgCheckOk({requestType: "new_delegate", orgCompanyCheck: "failed"}), false);
  assert.equal(L.requestApprovalOrgCheckOk({requestType: "new_delegate"}), false);
  assert.equal(L.requestApprovalOrgCheckOk({orgCompanyCheck: "failed"}), false); // default type is new_delegate
  assert.equal(L.requestApprovalOrgCheckOk({requestType: "renewal"}), true);
  assert.equal(L.requestApprovalOrgCheckOk({requestType: "delete_delegate", orgCompanyCheck: "failed"}), true);
});

test("delegateCreateCompanyMissing is true when the parent company doc is absent", () => {
  assert.equal(L.delegateCreateCompanyMissing({orgId: "oX", companyId: "c1", companyExists: false}), true);
  assert.equal(L.delegateCreateCompanyMissing({orgId: "o1", companyId: "c1", companyExists: true}), false);
  assert.equal(L.delegateCreateCompanyMissing({orgId: "", companyId: "c1", companyExists: true}), true);
});
