const {describe, test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  parseArgs, newBackfillRunId, refuseExistingOutputFile, writeJsonFileNew,
} = require("../scripts/p0-common");

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

describe("p0-common output file guards", () => {
  test("newBackfillRunId includes a unique hex suffix", () => {
    const a = newBackfillRunId("org-uids");
    const b = newBackfillRunId("org-uids");
    assert.match(a, /^org-uids-/);
    assert.notEqual(a, b);
    assert.match(a, /-[0-9a-f]{6}$/);
  });

  test("refuseExistingOutputFile rejects an existing rollback path", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "p0-guard-"));
    const file = path.join(dir, "rollback.json");
    fs.writeFileSync(file, "{}");
    assert.throws(
      () => refuseExistingOutputFile(file, "rollback"),
      /Refusing to overwrite existing rollback/,
    );
  });

  test("writeJsonFileNew writes once and refuses a second write", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "p0-write-"));
    const file = path.join(dir, "report.json");
    writeJsonFileNew(file, {ok: true}, "report");
    assert.throws(
      () => writeJsonFileNew(file, {ok: false}, "report"),
      /Refusing to overwrite existing report/,
    );
  });
});