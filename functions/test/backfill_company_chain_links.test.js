const test = require("node:test");
const assert = require("node:assert");
const {parseArgs, assertSafe} = require("../scripts/backfill-company-chain-links");

test("backfill guards: apply never on prod, prod dry run needs the flag", () => {
  const prod = "practice-firebase-72df1";
  assert.throws(() => assertSafe(parseArgs(["--project", prod, "--apply", "--read-only-prod"])), /never writes prod/);
  assert.throws(() => assertSafe(parseArgs(["--project", prod])), /read-only-prod/);
  assert.equal(assertSafe(parseArgs(["--project", prod, "--read-only-prod"])), prod);
  assert.equal(assertSafe(parseArgs(["--project", "tashil-dev", "--apply"])), "tashil-dev");
  assert.throws(() => assertSafe(parseArgs(["--project", "other"])), /Refusing/);
  assert.throws(() => assertSafe(parseArgs([])), /required/);
  assert.equal(parseArgs(["--project", "tashil-dev"]).apply, false);
});
