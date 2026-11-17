const test = require("node:test");
const assert = require("node:assert");
const {parseArgs, assertSafe} = require("../scripts/backfill-company-chain-links");

test("backfill guards: apply never on prod, prod dry run needs the flag", () => {
  const prod = "practice-firebase-72df1";
  assert.throws(() => assertSafe(parseArgs(["--project", prod, "--apply", "--read-only-prod"])), /allow-prod-project/);
  assert.throws(() => assertSafe(parseArgs(["--project", prod])), /read-only-prod/);
  assert.equal(assertSafe(parseArgs(["--project", prod, "--read-only-prod"])), prod);
  assert.equal(assertSafe(parseArgs(["--project", "tashil-dev", "--apply"])), "tashil-dev");
  assert.throws(() => assertSafe(parseArgs(["--project", "other"])), /Refusing/);
  assert.throws(() => assertSafe(parseArgs([])), /required/);
  assert.equal(parseArgs(["--project", "tashil-dev"]).apply, false);
});

test("backfill guards: prod apply only with company, allow flag and rollback", () => {
  const prod = "practice-firebase-72df1";
  const ok = ["--project", prod, "--apply", `--allow-prod-project=${prod}`, "--company", "c1", "--rollback", "rb.json"];
  assert.equal(assertSafe(parseArgs(ok)), prod);
  assert.throws(() => assertSafe(parseArgs(ok.filter((a) => a !== "--company" && a !== "c1"))), /--company/);
  assert.throws(() => assertSafe(parseArgs(ok.filter((a) => a !== "--rollback" && a !== "rb.json"))), /--rollback/);
  assert.throws(() => assertSafe(parseArgs(ok.filter((a) => !a.startsWith("--allow")))), /allow-prod-project/);
  assert.equal(assertSafe(parseArgs(["--project", prod, `--allow-prod-project=${prod}`, "--revert", "rb.json"])), prod);
});
