#!/usr/bin/env node
/**
 * Writes a firebase.json overlay with emulator ports from LOCAL_CI_* env.
 * Usage: node scripts/generate_emulator_firebase_config.js <outPath>
 *
 * Port env vars (see scripts/emulator_ports.env.sh):
 *   LOCAL_CI_FIRESTORE_PORT, LOCAL_CI_FIRESTORE_HUB_PORT, LOCAL_CI_AUTH_PORT,
 *   LOCAL_CI_STORAGE_PORT, LOCAL_CI_FUNCTIONS_PORT, LOCAL_CI_LOGGING_PORT,
 *   LOCAL_CI_FIRESTORE_WEBSOCKET_PORT
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
const absInRepo = (rel) =>
  path.isAbsolute(rel) ? rel : path.join(repoRoot, rel);
if (base.firestore?.rules) {
  base.firestore.rules = absInRepo(base.firestore.rules);
}
if (base.firestore?.indexes) {
  base.firestore.indexes = absInRepo(base.firestore.indexes);
}
if (base.storage?.rules) {
  base.storage.rules = absInRepo(base.storage.rules);
}
base.emulators = {
  firestore: {
    port: int("LOCAL_CI_FIRESTORE_PORT", 8080),
    websocketPort: int("LOCAL_CI_FIRESTORE_WEBSOCKET_PORT", 9150),
  },
  auth: {port: int("LOCAL_CI_AUTH_PORT", 9099)},
  storage: {port: int("LOCAL_CI_STORAGE_PORT", 9199)},
  functions: {port: int("LOCAL_CI_FUNCTIONS_PORT", 5001)},
  hub: {port: int("LOCAL_CI_FIRESTORE_HUB_PORT", 4400)},
  logging: {port: int("LOCAL_CI_LOGGING_PORT", 4500)},
  ui: {enabled: false},
};
fs.writeFileSync(outPath, JSON.stringify(base, null, 2));