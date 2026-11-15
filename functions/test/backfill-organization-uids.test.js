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

const {
  writtenFieldsOf, currentMatchesWritten, shouldRestore, isDeleteSentinel,
  atReadOf, changedSinceRead, shouldApplyWrite,
} = require("../scripts/backfill-organization-uids");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {writeJsonFileNew, refuseExistingOutputFile} = require("../scripts/p0-common");

describe("backfill organizationUIDs restore compare-before-write", () => {
  test("restores only when the live doc still holds the backfill write", () => {
    const entry = {
      path: "delegate_requests/r1",
      previous: {organizationUIDs: null, organizationNames: null},
      fields: {organizationUIDs: ["o1"], organizationNames: ["كارفور"]},
    };
    const unchanged = {
      organizationUID: "o1", organizationName: "كارفور",
      organizationUIDs: ["o1"], organizationNames: ["كارفور"],
    };
    assert.equal(shouldRestore(unchanged, entry).ok, true);

    const later = {
      organizationUID: "o1", organizationName: "كارفور",
      organizationUIDs: ["o1", "o2"], organizationNames: ["كارفور", "أخرى"],
    };
    const skip = shouldRestore(later, entry);
    assert.equal(skip.ok, false);
    assert.equal(skip.reason, "current_differs_from_written");
  });

  test("reconstructs the written fields from older rollback files", () => {
    const entry = {
      path: "delegate_requests/r2",
      previous: {organizationUIDs: null, organizationNames: null},
    };
    const current = {organizationUID: "o1", organizationName: "كارفور", organizationUIDs: ["o1"], organizationNames: ["كارفور"]};
    assert.deepEqual(writtenFieldsOf(entry, current), {organizationUIDs: ["o1"], organizationNames: ["كارفور"]});
    assert.equal(currentMatchesWritten(current, writtenFieldsOf(entry, current)), true);
    assert.equal(shouldRestore({...current, organizationUIDs: ["o1", "o2"]}, entry).ok, false);
  });

  test("isDeleteSentinel recognizes a FieldValue.delete patch", () => {
    const del = require("firebase-admin").firestore.FieldValue.delete();
    assert.equal(isDeleteSentinel(del), true);
    assert.equal(isDeleteSentinel(["o1"]), false);
  });
});

describe("backfill organizationUIDs apply changed-since-read", () => {
  test("shouldApplyWrite accepts an unchanged legacy doc", () => {
    const data = {organizationUID: "o1", organizationName: "كارفور"};
    const planned = {
      patch: {organizationUIDs: ["o1"], organizationNames: ["كارفور"]},
      atRead: atReadOf(data),
    };
    assert.equal(shouldApplyWrite(data, planned).ok, true);
  });

  test("shouldApplyWrite skips when organizationUIDs changed after scan", () => {
    const atScan = {organizationUID: "o1", organizationName: "كارفور"};
    const planned = {
      patch: {organizationUIDs: ["o1"], organizationNames: ["كارفور"]},
      atRead: atReadOf(atScan),
    };
    const live = {
      organizationUID: "o1",
      organizationName: "كارفور",
      organizationUIDs: ["o1", "o2"],
    };
    assert.equal(changedSinceRead(live, planned.atRead), true);
    const skip = shouldApplyWrite(live, planned);
    assert.equal(skip.ok, false);
    assert.equal(skip.reason, "changed_since_read");
  });

  test("rollback refuse guard blocks overwriting an existing file", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "org-uids-rb-"));
    const rollbackPath = path.join(dir, "organization-uids-rollback.json");
    writeJsonFileNew(rollbackPath, {entries: []}, "rollback");
    assert.throws(
      () => refuseExistingOutputFile(rollbackPath, "rollback"),
      /use a new path for each run/,
    );
  });
});
