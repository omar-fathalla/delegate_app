const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const {parseArgs} = require("../scripts/p0-common");

describe("p0-common parseArgs", () => {
  test("defaults to dry-run when neither --apply nor --dry-run is passed", () => {
    const a = parseArgs(["--project", "tashil-dev"]);
    assert.equal(a.apply, false);
    assert.equal(a.dryRun, false);
  });

  test("--dry-run is explicit and still leaves apply false", () => {
    const a = parseArgs(["--project=tashil-dev", "--dry-run", "--rollback", "/tmp/r.json"]);
    assert.equal(a.apply, false);
    assert.equal(a.dryRun, true);
    assert.deepEqual(a.rest, ["--rollback", "/tmp/r.json"]);
  });

  test("rejects --dry-run with --apply", () => {
    assert.throws(
      () => parseArgs(["--project", "tashil-dev", "--dry-run", "--apply"]),
      /--dry-run.*--apply/,
    );
  });
});