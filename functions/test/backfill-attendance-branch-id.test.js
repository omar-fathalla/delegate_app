const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeBranchName, buildBranchIndex, planRecord, previousOf, tally, newReport, parseArgs,
} = require("../scripts/backfill-attendance-branch-id");

const branch = (id, name, org, parentOrg = "") =>
  ({id, path: parentOrg ? `organizations/${parentOrg}/branches/${id}` : `branches/${id}`,
    data: {branchName: name, organizationUID: org}, parentOrg});

describe("TAS-335 attendance branchId backfill", () => {
  test("normalization matches the app rules plus the «فرع» prefix", () => {
    assert.equal(normalizeBranchName("  فرع  الإبراهيمية "), "الابراهيميه");
    assert.equal(normalizeBranchName("الابراهيميه"), "الابراهيميه");
    assert.equal(normalizeBranchName("المعادى"), "المعادي");
    assert.equal(normalizeBranchName("Fake  Branch"), "fake branch");
    assert.equal(normalizeBranchName(null), "");
  });

  const index = buildBranchIndex([
    branch("br-ibr", "الإبراهيمية", "org1"),
    branch("br-a", "سموحة", "org1"),
    branch("br-b", "فرع سموحه", "org1"),
    branch("br-nested", "العجمي", "", "org2"),
    branch("br-other", "الإبراهيمية", "org3"),
  ]);

  test("exactly one branch in the chain: patch branchId + branchOrganizationUID", () => {
    const plan = planRecord({organizationId: "org1", branchName: "فرع الابراهيميه"}, index);
    assert.equal(plan.status, "match");
    assert.deepEqual(plan.patch, {branchId: "br-ibr", branchOrganizationUID: "org1"});
  });

  test("keeps an existing branchOrganizationUID and reads nested branches", () => {
    const plan = planRecord({organizationId: "x", branchOrganizationUID: "org2", branchName: "العجمى"}, index);
    assert.deepEqual(plan.patch, {branchId: "br-nested"});
  });

  test("two branches with the same normalized name are ambiguous and not written", () => {
    const plan = planRecord({organizationId: "org1", branchName: "سموحة"}, index);
    assert.equal(plan.status, "ambiguous");
    assert.deepEqual(plan.candidates, ["br-a", "br-b"]);
    assert.equal(plan.patch, undefined);
  });

  test("never matches a branch of another chain", () => {
    assert.equal(planRecord({organizationId: "org9", branchName: "الإبراهيمية"}, index).status, "unmatched");
  });

  test("skips logs that already have a branchId, or have no name / chain", () => {
    assert.equal(planRecord({branchId: "x", branchName: "سموحة", organizationId: "org1"}, index).status, "has_id");
    assert.equal(planRecord({organizationId: "org1"}, index).status, "no_name");
    assert.equal(planRecord({branchName: "سموحة"}, index).status, "no_chain");
  });

  test("backup keeps previous values, null for absent fields", () => {
    assert.deepEqual(previousOf({branchOrganizationUID: ""}, {branchId: "a", branchOrganizationUID: "o"}),
        {branchId: null, branchOrganizationUID: ""});
  });

  test("report counts by month and keeps no people fields in examples", () => {
    const r = newReport({});
    const ts = {toDate: () => new Date("2026-11-20T10:00:00Z")};
    const data = {organizationId: "org9", branchName: "X", delegateName: "Someone", phoneNumber: "010", timestamp: ts};
    tally(r, "doc1", data, planRecord(data, index), 5, new Date("2026-11-25T00:00:00Z"));
    assert.equal(r.counts.unmatched, 1);
    assert.equal(r.missingByMonth["2026-11"], 1);
    assert.equal(r.missingLast30DaysByDay["2026-11-20"], 1);
    const ex = JSON.stringify(r.examples);
    assert.ok(!ex.includes("Someone") && !ex.includes("010"));
  });

  test("args: dry run by default, --apply needs a backup, prod apply needs the explicit flag", () => {
    assert.equal(parseArgs(["--project", "tashil-dev"]).apply, false);
    assert.throws(() => parseArgs([]), /--project is required/);
    assert.throws(() => parseArgs(["--project", "other-project"]), /unknown project/);
    assert.throws(() => parseArgs(["--project", "tashil-dev", "--apply"]), /--backup/);
    assert.throws(() => parseArgs(["--project", "practice-firebase-72df1", "--apply", "--backup", "b"]),
        /allow-prod-project/);
    assert.equal(parseArgs(["--project", "practice-firebase-72df1"]).apply, false);
  });
});
