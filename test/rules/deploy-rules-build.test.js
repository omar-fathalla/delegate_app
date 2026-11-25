// TAS-339: firebase.json deploys firestore.deploy.rules, built from
// firestore.rules by scripts/build_firestore_rules.js (comments and blank
// lines removed to stay under Google's ~6 s rules compile limit). Every other
// rules suite tests firestore.rules, so the deployed file must be the same
// ruleset: current with the source and token-for-token equal.
const {test} = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const {build, tokens, SRC, OUT} = require("../../scripts/build_firestore_rules.js");

const ROOT = path.join(__dirname, "../..");

test("firestore.deploy.rules is the current build of firestore.rules", () => {
  assert.ok(fs.existsSync(OUT), "missing firestore.deploy.rules: run node scripts/build_firestore_rules.js");
  assert.strictEqual(fs.readFileSync(OUT, "utf8"), build(),
    "firestore.deploy.rules is stale: run node scripts/build_firestore_rules.js and commit it");
});

test("the deployed file has exactly the source's tokens (no comment ate code)", () => {
  const a = tokens(fs.readFileSync(SRC, "utf8"));
  const b = tokens(fs.readFileSync(OUT, "utf8"));
  assert.strictEqual(b.length, a.length);
  assert.deepStrictEqual(b, a);
  assert.ok(!/\/\//.test(fs.readFileSync(OUT, "utf8").replace(/'(?:[^'\\\n]|\\.)*'/g, "''")),
    "a // comment survived outside a string");
});

test("firebase.json deploys the built file and checks it before deploy", () => {
  const fb = JSON.parse(fs.readFileSync(path.join(ROOT, "firebase.json"), "utf8"));
  assert.strictEqual(fb.firestore.rules, "firestore.deploy.rules");
  assert.ok((fb.firestore.predeploy || []).some((c) => c.includes("build_firestore_rules.js") && c.includes("--check")));
});
