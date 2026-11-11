const test = require("node:test");
const assert = require("node:assert/strict");
const {parseArgs} = require("../scripts/backfill-delegate-holds");
const {assertTarget} = require("../scripts/p0-common");

test("parseArgs defaults to dry-run and requires a project later", () => {
  const a = parseArgs(["--project", "tashil-dev"]);
  assert.equal(a.project, "tashil-dev");
  assert.equal(a.apply, false);
  assert.equal(a.revert, false);
});

test("parseArgs accepts apply, revert and rollback", () => {
  const a = parseArgs(["--project=tashil-dev", "--apply", "--revert", "--rollback", "./r.json"]);
  assert.equal(a.apply, true);
  assert.equal(a.revert, true);
  assert.equal(a.rollback, "./r.json");
});

test("assertTarget refuses prod without an explicit allow", () => {
  assert.equal(assertTarget({project: "tashil-dev", allowProd: ""}), "tashil-dev");
  assert.throws(() => assertTarget({project: "practice-firebase-72df1", allowProd: ""}));
});
