/**
 * Static guard: production function sources and operator scripts must not
 * write password / temporaryPassword / tempPassword onto users/* documents.
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

const SECRET_PROP = new RegExp(
  `\\b(?:${SECRET_KEYS.join("|")})\\s*:`,
  "m",
);

const USERS_WRITE = /collection\(['"]users['"]\)|\.doc\(['"]users\/|users\/\$\{/;

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
    if (ent.name.endsWith(".test.js") && !ALLOWLIST.has(path.relative(ROOT, full).split(path.sep).join("/"))) {
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
    if (!USERS_WRITE.test(text) || !SECRET_PROP.test(text)) continue;

    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!SECRET_PROP.test(line)) continue;
      if (/auth\(\)\.updateUser|\.updateUser\(/.test(line)) continue;
      if (/\.(get|log|hasOwnProperty)|data\./.test(line)) continue;
      if (/SECRET_KEYS|forbidden field|stores no password|never writes/i.test(line)) continue;
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