// Drop-in replacement for @firebase/rules-unit-testing used by every rules test
// (TAS-105). Same exports, plus a guard on Firestore's 1000-expression budget.
//
// The problem: when a rule runs out of its 1000-expression budget the request is
// denied, and a test using assertFails() passes. But that deny never came from a
// rule condition. Make a helper cheaper or reorder a condition and the same
// request can suddenly be ALLOWED. On 2026-11-20 about 350 assertFails() calls
// on dev were denied this way, mostly by three rules: delegates update (nested
// and collection group) and delegate_requests update.
//
// How it is enforced (RULES_BUDGET_MODE):
//   ratchet (default) — budget denials are counted per test file and compared
//                       with test/rules/expression-budget-baseline.json. More than
//                       the baseline fails the file; fewer prints a reminder to
//                       lower the baseline. New budget-only denies cannot land.
//   strict            — every budget denial fails its test (use while fixing).
//   record            — write the current counts into the baseline file.
//
// assertDeniedByRule() is always strict: use it for denies that must never rely
// on the budget (security-critical cases such as F14).
//
// Also exported: isBudgetDenial(err), assertBudgetHeadroom(opts), trueTree(n).
const fs = require("fs");
const path = require("path");
const base = require("@firebase/rules-unit-testing");

const BUDGET_RE = /maximum of 1000 expressions/i;
const BASELINE_FILE = path.join(__dirname, "expression-budget-baseline.json");
const MODE = (process.env.RULES_BUDGET_MODE || "ratchet").toLowerCase();

function isBudgetDenial(err) {
  if (!err) return false;
  const text = [err.message, err.details, err.customData && JSON.stringify(err.customData)]
    .filter(Boolean)
    .join("\n");
  return BUDGET_RE.test(text);
}

function budgetError(err) {
  const e = new Error(
    "Denied by the 1000-expression budget, not by a rule condition. " +
      "Add an explicit, cheap deny for this case (TAS-105).\n" + (err && err.message),
  );
  e.cause = err;
  return e;
}

// ---- per-file counting (ratchet / record) ----
const counts = new Map(); // test file basename -> budget denials
function callerTestFile() {
  // `node --test <file>` runs each file in its own process with the file in
  // argv: the most reliable source (async stacks can lose the test frame).
  const fromArgv = process.argv.find((a) => a.endsWith(".test.js"));
  if (fromArgv) return path.basename(fromArgv);
  const stack = new Error().stack.split("\n");
  for (const line of stack) {
    const m = line.match(/([^/\\\s(]+\.test\.js)/);
    if (m) return m[1];
  }
  return "unknown.test.js";
}

let exitHookInstalled = false;
function installExitHook() {
  if (exitHookInstalled) return;
  exitHookInstalled = true;
  process.on("exit", () => {
    let baseline = {};
    try { baseline = JSON.parse(fs.readFileSync(BASELINE_FILE, "utf8")); } catch {}
    if (MODE === "record") {
      for (const [file, n] of counts) baseline[file] = n;
      const sorted = Object.fromEntries(Object.entries(baseline).sort(([a], [b]) => a.localeCompare(b)));
      fs.writeFileSync(BASELINE_FILE, JSON.stringify(sorted, null, 2) + "\n");
      for (const [file, n] of counts) console.error(`[rules budget] recorded ${file}: ${n}`);
      return;
    }
    for (const [file, n] of counts) {
      const allowed = baseline[file] ?? 0;
      if (n > allowed) {
        console.error(
          `[rules budget] ${file}: ${n} denials came from the 1000-expression budget, ` +
            `baseline allows ${allowed}. A new deny relies on the budget: make it explicit (TAS-105). ` +
            `Run with RULES_BUDGET_MODE=strict to see which.`,
        );
        process.exitCode = 1;
      } else if (n < allowed) {
        console.error(`[rules budget] ${file}: ${n} budget denials, baseline ${allowed}. Lower the baseline ` +
          `(RULES_BUDGET_MODE=record) so the gain cannot be lost.`);
      }
    }
  });
}

async function assertFails(pr) {
  const err = await base.assertFails(pr);
  if (isBudgetDenial(err)) {
    if (MODE === "strict") throw budgetError(err);
    const file = callerTestFile();
    counts.set(file, (counts.get(file) || 0) + 1);
    installExitHook();
  }
  return err;
}

/** Like assertFails, but a budget denial always fails, whatever the mode. */
async function assertDeniedByRule(pr) {
  const err = await base.assertFails(pr);
  if (isBudgetDenial(err)) throw budgetError(err);
  return err;
}

// Balanced tree of `true` so the padding cannot hit nesting limits: n leaves.
function trueTree(n) {
  if (n <= 1) return "true";
  const left = Math.floor(n / 2);
  return `(${trueTree(left)} && ${trueTree(n - left)})`;
}

/**
 * Proves a rule keeps `pad` spare expressions for a real, allowed request.
 * @param {object} o
 * @param {string} o.rules     full rules source
 * @param {string} o.line      rules text that appears exactly once; the last
 *                             `allow ...: if ` inside it is padded (earlier
 *                             lines are context, to make the text unique)
 * @param {number} o.pad       spare pad units required (trueTree(pad) is inserted)
 * @param {string} o.projectId demo-* project id for the throwaway env
 * @param {(db, env) => Promise<void>} [o.seed] fixtures, written with rules disabled
 * @param {(env) => Promise<unknown>} o.request request that must still be allowed
 */
async function assertBudgetHeadroom({rules, line, pad, projectId, seed, request}) {
  const count = rules.split(line).length - 1;
  if (count !== 1) throw new Error(`headroom guard: expected the rule text once, found ${count}; update the guard`);
  const all = [...line.matchAll(/allow [a-z, ]+: if /g)];
  if (!all.length) throw new Error("headroom guard: rule text must contain `allow <ops>: if `");
  const last = all[all.length - 1]; // earlier lines are context only
  const at = last.index + last[0].length;
  const padded = rules.replace(line, line.slice(0, at) + `${trueTree(pad)} && ` + line.slice(at));
  const env = await base.initializeTestEnvironment({projectId, firestore: {rules: padded}});
  try {
    if (seed) await env.withSecurityRulesDisabled((ctx) => seed(ctx.firestore(), env));
    await base.assertSucceeds(request(env));
  } finally {
    await env.cleanup();
  }
}

module.exports = {...base, assertFails, assertDeniedByRule, isBudgetDenial, assertBudgetHeadroom, trueTree};
