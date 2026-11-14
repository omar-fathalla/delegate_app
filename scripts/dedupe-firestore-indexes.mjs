#!/usr/bin/env node
/**
 * Deduplicate firestore.indexes.json and strip invalid single-field composites.
 * Usage: node scripts/dedupe-firestore-indexes.mjs [--write] [firestore.indexes.json]
 */
import { readFileSync, writeFileSync } from "fs";

const write = process.argv.includes("--write");
const path = process.argv.find((a) => a.endsWith(".json")) ?? "firestore.indexes.json";
const raw = JSON.parse(readFileSync(path, "utf8"));

function semanticKey(idx) {
  const fields = (idx.fields ?? [])
    .filter((f) => f.fieldPath !== "__name__")
    .map((f) => `${f.fieldPath}:${f.order ?? f.arrayConfig ?? ""}`)
    .join("|");
  return `${idx.collectionGroup}|${idx.queryScope}|${fields}`;
}

function isSingleFieldComposite(idx) {
  const fields = (idx.fields ?? []).filter((f) => f.fieldPath !== "__name__");
  return fields.length === 1;
}

const removed = { singleField: [], duplicates: [] };
const seen = new Map();
const kept = [];

for (let i = 0; i < raw.indexes.length; i++) {
  const idx = raw.indexes[i];
  if (isSingleFieldComposite(idx)) {
    removed.singleField.push({ index: i, def: idx });
    continue;
  }
  const key = semanticKey(idx);
  if (seen.has(key)) {
    removed.duplicates.push({ index: i, firstAt: seen.get(key), key, def: idx });
    continue;
  }
  seen.set(key, i);
  kept.push(idx);
}

console.log(`Total indexes: ${raw.indexes.length}`);
console.log(`After cleanup: ${kept.length}`);
console.log(`Removed single-field composites: ${removed.singleField.length}`);
for (const r of removed.singleField) {
  console.log(
    `  - [${r.index}] ${r.def.collectionGroup} ${r.def.queryScope} fields=${JSON.stringify(r.def.fields)}`,
  );
}
console.log(`Removed semantic duplicates: ${removed.duplicates.length}`);
for (const r of removed.duplicates) {
  console.log(`  - [${r.index}] dup of [${r.firstAt}] ${r.key}`);
}

if (write) {
  raw.indexes = kept;
  writeFileSync(path, `${JSON.stringify(raw, null, 2)}\n`, "utf8");
  console.log(`Wrote ${path}`);
}