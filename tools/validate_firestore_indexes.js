#!/usr/bin/env node
/**
 * Validates firestore.indexes.json for deploy (firebase deploy --only firestore:indexes).
 * - Rejects composite indexes with only one field (use fieldOverrides for single-field).
 * - Removes exact duplicate composite definitions (stable: keeps first).
 */
const fs = require("fs");
const path = require("path");

const indexesPath = path.join(__dirname, "..", "firestore.indexes.json");

function indexKey(idx) {
  const fields = (idx.fields || []).map((f) => ({
    fieldPath: f.fieldPath,
    order: f.order,
    arrayConfig: f.arrayConfig,
  }));
  return JSON.stringify({
    collectionGroup: idx.collectionGroup,
    queryScope: idx.queryScope || "COLLECTION",
    fields,
    density: idx.density,
  });
}

function load() {
  return JSON.parse(fs.readFileSync(indexesPath, "utf8"));
}

function validate(doc) {
  const errors = [];
  const seen = new Set();
  const dupes = [];

  for (let i = 0; i < doc.indexes.length; i++) {
    const idx = doc.indexes[i];
  if (!idx.fields || idx.fields.length < 2) {
      errors.push(
        `indexes[${i}]: single-field composite on ${idx.collectionGroup} ` +
          `(${idx.fields?.[0]?.fieldPath}) — remove or use fieldOverrides`,
      );
    }
    const key = indexKey(idx);
    if (seen.has(key)) dupes.push(i);
    else seen.add(key);
  }

  return {errors, dupes, unique: seen.size};
}

function main() {
  const doc = load();
  const {errors, dupes, unique} = validate(doc);
  const apply = process.argv.includes("--apply");

  if (dupes.length && apply) {
    const keep = new Set();
    const out = [];
    for (let i = 0; i < doc.indexes.length; i++) {
      const idx = doc.indexes[i];
      const key = indexKey(idx);
      if (keep.has(key)) continue;
      keep.add(key);
      out.push(idx);
    }
    doc.indexes = out;
    fs.writeFileSync(indexesPath, `${JSON.stringify(doc, null, 2)}\n`);
  }

  const after = apply ? load() : doc;
  const final = validate(after);

  console.log(
    JSON.stringify({
      path: indexesPath,
      compositeCount: after.indexes.length,
      uniqueComposites: final.unique,
      singleFieldComposites: final.errors.length,
      duplicateIndices: final.dupes.length,
      ok: final.errors.length === 0 && final.dupes.length === 0,
    }, null, 2),
  );

  if (final.errors.length) {
    for (const e of final.errors) console.error(e);
    process.exit(1);
  }
  if (final.dupes.length && !apply) {
    console.error("Run with --apply to drop exact duplicate composite entries.");
    process.exit(1);
  }
}

main();