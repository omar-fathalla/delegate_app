/**
 * One-off backfill: stamp `branchKey` on attendance_logs docs that lack it.
 *
 * `branchKey` = normalized `branchName` (must match lib/core/utils/branch_key.dart):
 *   trim → lowercase → [أإآ]→ا, ة→ه, ى→ي → collapse whitespace.
 *
 * Local Admin-SDK script. NOT deployed. Idempotent (never overwrites an
 * existing branchKey). Pages by document id (500/page) with a checkpoint
 * file so an interrupted --commit run resumes where it stopped. Dry-runs
 * start fresh unless --resume; --no-resume forces a fresh --commit scan.
 * A completed run deletes its checkpoint.
 *
 * DEFAULT IS DRY-RUN: reads only, logs counts + samples, writes nothing.
 * Writing requires BOTH `--commit` and, outside the emulator,
 * `--i-understand-prod`. Only Mohamed runs `--commit`.
 *
 *   node scripts/backfill_branch_key.js                       # dry-run
 *   node scripts/backfill_branch_key.js --collection attendance_logs_testing
 *   node scripts/backfill_branch_key.js --commit --i-understand-prod
 *
 * Cost: ~1 read per doc scanned (+1 write per doc updated with --commit).
 */

"use strict";

const fs = require("fs");
const path = require("path");

const ALLOWED_COLLECTIONS = ["attendance_logs", "attendance_logs_testing"];

function branchKey(name) {
  if (typeof name !== "string") return "";
  return name
    .trim()
    .toLowerCase()
    .replace(/[أإآ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/\s+/g, " ");
}

/** Returns the patch for one doc, or null when nothing to write. */
function branchKeyPatch(data) {
  if (!data || typeof data !== "object") return null;
  if (typeof data.branchKey === "string" && data.branchKey !== "") return null;
  const key = branchKey(data.branchName);
  if (!key) return null;
  return {branchKey: key};
}

function parseArgs(argv) {
  const out = {
    commit: false,
    allowProd: false,
    collection: "attendance_logs",
    pageSize: 500,
    maxPages: Infinity,
    checkpoint: path.join(process.cwd(), "backfill-branch-key.checkpoint.json"),
    report: path.join(process.cwd(), "backfill-branch-key-report.json"),
    // null → default: resume only for --commit runs (dry-runs start fresh).
    resume: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--commit") out.commit = true;
    else if (a === "--dry-run") out.commit = false;
    else if (a === "--i-understand-prod") out.allowProd = true;
    else if (a === "--collection") out.collection = argv[++i];
    else if (a === "--page-size") out.pageSize = Number(argv[++i]);
    else if (a === "--max-pages") out.maxPages = Number(argv[++i]);
    else if (a === "--checkpoint") out.checkpoint = argv[++i];
    else if (a === "--report") out.report = argv[++i];
    else if (a === "--no-resume") out.resume = false;
    else if (a === "--resume") out.resume = true;
    else if (a === "--help" || a === "-h") out.help = true;
    else throw new Error(`Unknown argument ${a}`);
  }
  // --dry-run anywhere wins over --commit.
  if (argv.includes("--dry-run")) out.commit = false;
  if (out.resume === null) out.resume = out.commit;
  return out;
}

/** Throws when the options would allow an unsafe write. */
function assertSafe(opts, emulatorHost) {
  if (!ALLOWED_COLLECTIONS.includes(opts.collection)) {
    throw new Error(`Refusing collection=${opts.collection}`);
  }
  if (!(opts.pageSize > 0 && opts.pageSize <= 500)) {
    throw new Error("--page-size must be 1..500");
  }
  if (opts.commit && !emulatorHost && !opts.allowProd) {
    throw new Error("Refusing --commit outside the emulator without --i-understand-prod.");
  }
  if (emulatorHost && opts.allowProd) {
    throw new Error("Conflicting: emulator + --i-understand-prod.");
  }
}

async function run(db, admin, opts, log = console.log) {
  const report = {
    startedAt: new Date().toISOString(),
    mode: opts.commit ? "commit" : "dry-run",
    collection: opts.collection,
    scanned: 0,
    alreadyKeyed: 0,
    noBranchName: 0,
    wouldUpdate: 0,
    updated: 0,
    pages: 0,
    distinctKeys: {},
    samples: [],
    lastDocId: null,
  };
  let cursor = null;
  if (opts.resume && opts.checkpoint && fs.existsSync(opts.checkpoint)) {
    const cp = JSON.parse(fs.readFileSync(opts.checkpoint, "utf8"));
    if (cp.collection === opts.collection && cp.mode === report.mode) cursor = cp.lastDocId;
  }
  const idField = admin.firestore.FieldPath.documentId();
  while (report.pages < opts.maxPages) {
    let q = db.collection(opts.collection).orderBy(idField).limit(opts.pageSize);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) {
      report.completed = true;
      break;
    }
    report.pages++;
    const batch = opts.commit ? db.batch() : null;
    let writes = 0;
    for (const doc of snap.docs) {
      report.scanned++;
      const data = doc.data();
      if (typeof data.branchKey === "string" && data.branchKey !== "") {
        report.alreadyKeyed++;
        continue;
      }
      const patch = branchKeyPatch(data);
      if (!patch) {
        report.noBranchName++;
        continue;
      }
      report.wouldUpdate++;
      report.distinctKeys[patch.branchKey] = (report.distinctKeys[patch.branchKey] || 0) + 1;
      if (report.samples.length < 20) {
        report.samples.push({id: doc.id, branchName: data.branchName, branchKey: patch.branchKey});
      }
      if (batch) {
        batch.update(doc.ref, patch);
        writes++;
      }
    }
    if (batch && writes > 0) {
      await batch.commit();
      report.updated += writes;
    }
    cursor = snap.docs[snap.docs.length - 1].id;
    report.lastDocId = cursor;
    if (opts.checkpoint) {
      fs.writeFileSync(opts.checkpoint, JSON.stringify({
        collection: opts.collection, mode: report.mode, lastDocId: cursor,
      }));
    }
    log(`page ${report.pages}: scanned=${report.scanned} wouldUpdate=${report.wouldUpdate} updated=${report.updated}`);
    if (snap.size < opts.pageSize) {
      report.completed = true;
      break;
    }
  }
  // Finished the whole collection: drop the checkpoint so the next run
  // (e.g. a verification dry-run) scans everything instead of reporting 0.
  if (report.completed && opts.checkpoint && fs.existsSync(opts.checkpoint)) {
    fs.unlinkSync(opts.checkpoint);
  }
  report.finishedAt = new Date().toISOString();
  return report;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log("See file header for usage.");
    return;
  }
  const emulator = process.env.FIRESTORE_EMULATOR_HOST || "";
  assertSafe(opts, emulator);
  const admin = require("firebase-admin");
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "practice-firebase-72df1"});
  }
  const db = admin.firestore();
  console.log(`mode=${opts.commit ? "COMMIT" : "dry-run"} collection=${opts.collection} emulator=${emulator || "no"}`);
  const report = await run(db, admin, opts);
  fs.writeFileSync(opts.report, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({
    mode: report.mode, scanned: report.scanned, alreadyKeyed: report.alreadyKeyed,
    noBranchName: report.noBranchName, wouldUpdate: report.wouldUpdate, updated: report.updated,
    distinctKeys: Object.keys(report.distinctKeys).length,
  }, null, 2));
}

module.exports = {branchKey, branchKeyPatch, parseArgs, assertSafe, run, ALLOWED_COLLECTIONS};

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}
