#!/usr/bin/env node
// TAS-339: build the deployed Firestore rules from the commented source.
//
// Google refuses a ruleset whose compile takes more than about 6 s
// (503 UNAVAILABLE on rulesets.create / release), and the compile time
// grows with the text size: the comments alone cost ~10-15%. firestore.rules
// stays the source (edit it, keep its comments); this writes
// firestore.deploy.rules with every // comment, blank line and leading /
// trailing space removed, and nothing else changed. firebase.json deploys
// the built file.
//
//   node scripts/build_firestore_rules.js          write firestore.deploy.rules
//   node scripts/build_firestore_rules.js --check  exit 1 if it is stale
//
// test/rules/deploy-rules-build.test.js checks in CI that the built file is
// current and has exactly the source's tokens (so every rules test of the
// source holds for the deployed file).
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const SRC = path.join(ROOT, "firestore.rules");
const OUT = path.join(ROOT, "firestore.deploy.rules");

// One token at a time: a comment, a quoted string (kept as is, so `//`
// inside a regex or URL string is never cut), or any other character.
const LEX = /\/\/[^\n]*|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|[\s\S]/g;

function strip(src) {
  let out = "";
  for (const m of src.matchAll(LEX)) {
    if (!m[0].startsWith("//")) out += m[0];
  }
  return out
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "")
    .join("\n") + "\n";
}

// Tokens without comments and whitespace: equal token lists mean the two
// files are the same ruleset.
function tokens(src) {
  const t = [];
  const re = /\/\/[^\n]*|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|\s+|[A-Za-z_0-9]+|[\s\S]/g;
  for (const m of src.matchAll(re)) {
    if (m[0].startsWith("//") || /^\s+$/.test(m[0])) continue;
    t.push(m[0]);
  }
  return t;
}

function build() {
  return strip(fs.readFileSync(SRC, "utf8"));
}

if (require.main === module) {
  const built = build();
  if (process.argv.includes("--check")) {
    const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
    if (cur !== built) {
      console.error("firestore.deploy.rules is stale: run node scripts/build_firestore_rules.js");
      process.exit(1);
    }
    console.log("firestore.deploy.rules is current");
  } else {
    fs.writeFileSync(OUT, built);
    console.log(`wrote firestore.deploy.rules (${built.length} bytes, source ${fs.statSync(SRC).size})`);
  }
}

module.exports = {strip, tokens, build, SRC, OUT};
