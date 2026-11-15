#!/usr/bin/env node
/**
 * Writes a firebase.json overlay with emulator ports from LOCAL_CI_* env.
 * Usage: node scripts/generate_emulator_firebase_config.js <outPath>
 */
const fs = require("fs");
const path = require("path");

const outPath = process.argv[2];
if (!outPath) {
  console.error("usage: generate_emulator_firebase_config.js <outPath>");
  process.exit(2);
}

const int = (name, fallback) => {
  const v = Number(process.env[name] ?? fallback);
  return Number.isInteger(v) && v > 0 ? v : fallback;
};

const repoRoot = path.join(__dirname, "..");
const base = JSON.parse(fs.readFileSync(path.join(repoRoot, "firebase.json"), "utf8"));
base.emulators = {
  firestore: {port: int("LOCAL_CI_FIRESTORE_PORT", 8080)},
  auth: {port: int("LOCAL_CI_AUTH_PORT", 9099)},
  storage: {port: int("LOCAL_CI_STORAGE_PORT", 9199)},
  functions: {port: int("LOCAL_CI_FUNCTIONS_PORT", 5001)},
  hub: {port: int("LOCAL_CI_FIRESTORE_HUB_PORT", 4400)},
  ui: {enabled: false},
};
fs.writeFileSync(outPath, JSON.stringify(base, null, 2));