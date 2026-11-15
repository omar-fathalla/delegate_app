/**
 * Static guard: production function sources and operator scripts must not
 * write password / temporaryPassword / tempPassword onto users/* documents.
 *
 * Limitation: computed keys with a variable (e.g. `{[k]: v}`) are not detected.
 * Literal property names, dotted `password.foo`, quoted `"password.hash"`, and
 * bracket literals like `['password']` are covered.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {SECRET_KEYS} = require("../scripts/p0-common");

const ROOT = path.join(__dirname, "..");

/** Files that intentionally seed legacy secrets for purge / rules tests. */
const ALLOWLIST = new Set([
  path.normalize("scripts/p0-scripts.emulator.test.js"),
  path.normalize("test/list_global_notify_staff.test.js"),
]);

const ESCAPED = SECRET_KEYS.map((k) => k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
const SECRET_LITERAL = new RegExp(
  `\\b(?:${ESCAPED.join("|")})(?:\\.\\w+)?\\s*:`,
  "m",
);
const SECRET_BRACKET_PROP = new RegExp(
  `\\[(['"])(?:${ESCAPED.join("|")})\\1\\]\\s*:`,
  "m",
);
const SECRET_BRACKET_ASSIGN = new RegExp(
  `\\[(['"])(?:${ESCAPED.join("|")})\\1\\]\\s*=`,
  "m",
);
const SECRET_QUOTED_DOTTED = new RegExp(
  `['"](?:${ESCAPED.join("|")})\\.\\w+['"]\\s*:`,
  "m",
);
const SECRET_COMPUTED_OBJ = new RegExp(
  `\\{\\s*\\[\\s*(?:['"])(?:${ESCAPED.join("|")})(?:['"])\\s*\\]\\s*:`,
  "m",
);

const USERS_WRITE = /collection\(['"]users['"]\)|\.doc\(['"]users\/|users\/\$\{/;

/**
 * @param {string} line
 * @return {boolean}
 */
function lineHasSecretKeyPattern(line) {
  return SECRET_LITERAL.test(line) ||
    SECRET_BRACKET_PROP.test(line) ||
    SECRET_BRACKET_ASSIGN.test(line) ||
    SECRET_QUOTED_DOTTED.test(line) ||
    SECRET_COMPUTED_OBJ.test(line);
}

/**
 * @param {string} dir
 * @param {string[]} acc
 */
function walkJsTs(dir, acc) {
  for (const ent of fs.readdirSync(dir, {withFileTypes: true})) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (ent.name === "node_modules" || ent.name === "lib") continue;
      walkJsTs(full, acc);
      continue;
    }
    if (!/\.(js|ts)$/.test(ent.name)) continue;
    const rel = path.relative(ROOT, full).split(path.sep).join("/");
    if (ent.name.endsWith(".test.js") && !ALLOWLIST.has(rel)) {
      continue;
    }
    acc.push(full);
  }
}

test("no users/* writes include secret password field keys", () => {
  const files = [];
  walkJsTs(path.join(ROOT, "src"), files);
  walkJsTs(path.join(ROOT, "scripts"), files);
  for (const name of fs.readdirSync(ROOT)) {
    if (/\.js$/.test(name) && name !== "package.json") {
      files.push(path.join(ROOT, name));
    }
  }

  /** @type {{file: string, line: number, text: string}[]} */
  const violations = [];
  for (const file of files) {
    const rel = path.relative(ROOT, file).split(path.sep).join("/");
    if (ALLOWLIST.has(rel)) continue;
    const text = fs.readFileSync(file, "utf8");
    if (!USERS_WRITE.test(text)) continue;
    if (!lineHasSecretKeyPattern(text)) continue;

    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!lineHasSecretKeyPattern(line)) continue;
      if (/auth\(\)\.updateUser|\.updateUser\(/.test(line)) continue;
      if (/\.(get|log|hasOwnProperty)|data\./.test(line)) continue;
      if (/SECRET_KEYS|forbidden field|stores no password|never writes|Variable-key/i.test(line)) continue;
      const slice = lines.slice(Math.max(0, i - 25), Math.min(lines.length, i + 10)).join("\n");
      if (!USERS_WRITE.test(slice)) continue;
      if (!/\.(set|update|add|create)\(|tx\.(set|update)\(/m.test(slice)) continue;
      violations.push({file: rel, line: i + 1, text: line.trim()});
    }
  }

  assert.deepEqual(
    violations,
    [],
    violations.map((v) => `${v.file}:${v.line} ${v.text}`).join("\n"),
  );
});

test("guard helper matches dotted and bracket literal keys", () => {
  assert.ok(lineHasSecretKeyPattern("  password.legacy: x,"));
  assert.ok(lineHasSecretKeyPattern('  "password.hash": x'));
  assert.ok(lineHasSecretKeyPattern("  ['temporaryPassword']: v"));
  assert.ok(lineHasSecretKeyPattern('  ["tempPassword"] = x'));
  assert.ok(!lineHasSecretKeyPattern("  data.password"));
  assert.ok(lineHasSecretKeyPattern('  {[ "password" ]: v'));
  assert.ok(!lineHasSecretKeyPattern("  {[key]: v"));
});