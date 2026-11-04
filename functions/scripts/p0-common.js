/**
 * Shared guards for the P0 users-write scripts. Not imported by index.js,
 * not deployed. Every script defaults to a dry run that prints counts only.
 */
const PROD_PROJECTS = new Set(["practice-firebase-72df1"]);
const SECRET_KEYS = ["password", "temporaryPassword", "tempPassword"];

/**
 * @param {string[]} argv
 * @return {{project: string, apply: boolean, allowProd: boolean, rest: string[]}}
 */
function parseArgs(argv) {
  const out = {project: "", apply: false, allowProd: false, rest: []};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--apply") out.apply = true;
    else if (a === "--allow-prod") out.allowProd = true;
    else if (a === "--project") out.project = argv[++i] || "";
    else if (a.startsWith("--project=")) out.project = a.slice(10);
    else out.rest.push(a);
  }
  return out;
}

/**
 * Throws unless the target project is explicit and not prod (prod also
 * needs --allow-prod, which must only be used after written approval).
 * @param {{project: string, allowProd: boolean}} args
 */
function assertTarget(args) {
  if (!args.project) throw new Error("--project is required (no default project).");
  if (PROD_PROJECTS.has(args.project) && !args.allowProd) {
    throw new Error(`Refusing to run on prod (${args.project}). Not approved.`);
  }
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

module.exports = {PROD_PROJECTS, SECRET_KEYS, parseArgs, assertTarget, secretKeysPresent, roleKey, resetPriority};
