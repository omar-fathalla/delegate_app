const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {planPatch} = require("../scripts/backfill-organization-uids");

describe("backfill organizationUIDs planPatch", () => {
  test("fills a legacy request that only has organizationUID", () => {
    const patch = planPatch({organizationUID: "o1", organizationName: "كارفور"});
    assert.deepEqual(patch, {organizationUIDs: ["o1"], organizationNames: ["كارفور"]});
  });

  test("skips a request that already has organizationUIDs", () => {
    assert.equal(planPatch({organizationUID: "o1", organizationUIDs: ["o1", "o2"]}), null);
  });

  test("skips a request with no organizationUID", () => {
    assert.equal(planPatch({organizationName: "x"}), null);
  });
});
