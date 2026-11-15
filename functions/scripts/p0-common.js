/**
 * Shared guards for the P0 users-write scripts. Not imported by index.js,
 * not deployed. Every script defaults to a dry run that prints counts only.
 */
const fs = require("fs");
const {randomBytes} = require("crypto");
const PROD_PROJECTS = new Set(["practice-firebase-72df1"]);
// Allow-list: only these targets run. Anything else (typos, case/space
// variants, "projects/..." paths, project numbers) is refused.
const ALLOWED_PROJECTS = new Set(["tashil-dev"]);
const DEMO_PROJECT = /^demo-[a-z0-9-]{1,40}$/; // emulator-only ids
const SECRET_KEYS = ["password", "temporaryPassword", "tempPassword"];

/** @param {unknown} raw @return {string} */
function normalizeProject(raw) {
  return typeof raw === "string" ? raw.trim().toLowerCase().replace(/^projects\//, "") : "";
}

/**
 * @param {string[]} argv
 * @return {{project: string, apply: boolean, dryRun: boolean, allowProd: string, rest: string[]}}
 */
function parseArgs(argv) {
  const out = {project: "", apply: false, dryRun: false, allowProd: "", rest: []};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--apply") out.apply = true;
    else if (a === "--dry-run") out.dryRun = true;
    else if (a.startsWith("--allow-prod-project=")) out.allowProd = normalizeProject(a.slice(21));
    else if (a === "--project") out.project = normalizeProject(argv[++i]);
    else if (a.startsWith("--project=")) out.project = normalizeProject(a.slice(10));
    else out.rest.push(a);
  }
  if (out.dryRun && out.apply) {
    throw new Error("Cannot use --dry-run together with --apply.");
  }
  return out;
}

/**
 * Throws unless the normalized project is allow-listed. Prod is refused
 * unless --allow-prod-project=<the same prod id> is passed, which must only
 * happen after written approval (not approved today).
 * @param {{project: string, allowProd: string}} args
 * @return {string} the project id to use
 */
function assertTarget(args) {
  const p = args.project;
  if (!p) throw new Error("--project is required (no default project).");
  if (ALLOWED_PROJECTS.has(p) || DEMO_PROJECT.test(p)) return p;
  if (PROD_PROJECTS.has(p) && args.allowProd === p) return p;
  throw new Error(`Refusing project "${p}": not on the allow-list (tashil-dev, demo-*).`);
}

/** @param {Record<string, unknown>} data @return {string[]} */
function secretKeysPresent(data) {
  return SECRET_KEYS.filter((k) => Object.prototype.hasOwnProperty.call(data || {}, k));
}

/** @param {unknown} role @return {string} */
function roleKey(role) {
  return typeof role === "string" ? role.trim().toLowerCase().replace(/-/g, "_") : "(none)";
}

const SUPER = new Set(["super_admin", "superadmin"]);
const FIELD = new Set(["delegate", "promoter", "(none)", ""]);

/** Super-admins first, then other staff; field roles are skipped. */
function resetPriority(role) {
  const k = roleKey(role);
  if (SUPER.has(k)) return 0;
  if (FIELD.has(k)) return -1;
  return 1;
}

/** @param {string} prefix */
function newBackfillRunId(prefix) {
  const t = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  return `${prefix}-${t}-${randomBytes(3).toString("hex")}`;
}

/**
 * Refuses to clobber an on-disk artifact from a prior run.
 * @param {string} filePath
 * @param {"rollback"|"report"} kind
 */
function refuseExistingOutputFile(filePath, kind) {
  if (!filePath) return;
  if (fs.existsSync(filePath)) {
    throw new Error(
      `Refusing to overwrite existing ${kind} file (use a new path for each run): ${filePath}`,
    );
  }
}

/** @param {string} filePath @param {unknown} data */
function writeJsonFileNew(filePath, data, kind = "rollback") {
  if (!filePath) throw new Error(`${kind} file path is required`);
  try {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), {flag: "wx"});
  } catch (e) {
    if (e && e.code === "EEXIST") {
      throw new Error(
        `Refusing to overwrite existing ${kind} file (use a new path for each run): ${filePath}`,
      );
    }
    throw e;
  }
}

/** Overwrite-safe report for failed or partial apply runs (TA-43). */
function writeJsonFilePartial(filePath, data) {
  if (!filePath) throw new Error("report file path is required");
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

module.exports = {
  PROD_PROJECTS,
  ALLOWED_PROJECTS,
  normalizeProject,
  SECRET_KEYS,
  parseArgs,
  assertTarget,
  secretKeysPresent,
  roleKey,
  resetPriority,
  newBackfillRunId,
  refuseExistingOutputFile,
  writeJsonFileNew,
  writeJsonFilePartial,
};
