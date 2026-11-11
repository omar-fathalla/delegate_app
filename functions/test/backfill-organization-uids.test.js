const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {planPatch, planRestore} = require("../scripts/backfill-organization-uids");

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

describe("backfill organizationUIDs planRestore", () => {
  test("deletes fields that were previously absent", () => {
    const patch = planRestore({organizationUIDs: null, organizationNames: null});
    const del = require("firebase-admin").firestore.FieldValue.delete();
    assert.ok(patch.organizationUIDs.isEqual(del));
    assert.ok(patch.organizationNames.isEqual(del));
  });

  test("writes back the previous arrays", () => {
    const patch = planRestore({organizationUIDs: ["o1"], organizationNames: ["كارفور"]});
    assert.deepEqual(patch, {organizationUIDs: ["o1"], organizationNames: ["كارفور"]});
  });
});
