/**
 * Backfill holds, source, rejectionReason and statusVersion on nested
 * delegate docs (Phase 2 item 1). Shadow mode: never writes status or
 * statusReason.
 *
 * Dry-run by default. The console prints counts only; the report/rollback
 * files may include document paths and uids, never names, phones, or
 * national IDs.
 *
 *   node scripts/backfill-delegate-holds.js --project tashil-dev
 *   node scripts/backfill-delegate-holds.js --project tashil-dev --rollback ./rollback.json
 *   node scripts/backfill-delegate-holds.js --project tashil-dev --apply --rollback ./rollback.json
 *   node scripts/backfill-delegate-holds.js --project tashil-dev --revert --rollback ./rollback.json
 *
 * Never runs against practice-firebase-72df1 unless a later, explicit
 * written go passes --allow-prod-project=practice-firebase-72df1.
 * Requires `npm run build` in functions/ first (loads lib/holds).
 */
"use strict";

const fs = require("fs");
const path = require("path");
const {randomBytes} = require("crypto");
const {parseArgs: parseCommonArgs, assertTarget, PROD_PROJECTS} =
  require("./p0-common");

function loadLogic() {
  const compiled = path.join(__dirname, "../lib/holds.js");
  if (!fs.existsSync(compiled)) {
    throw new Error("Missing functions/lib/holds.js — run npm run build in functions/ first.");
  }
  return require("../lib/holds");
}

function parseArgs(argv) {
  const common = parseCommonArgs(argv);
  const out = {
    project: common.project,
    apply: common.apply,
    allowProd: common.allowProd,
    revert: false,
    report: "",
    rollback: "",
    pageSize: 200,
  };
  const rest = common.rest;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--revert") out.revert = true;
    else if (a === "--report") out.report = rest[++i] || "";
    else if (a.startsWith("--report=")) out.report = a.slice(9);
    else if (a === "--rollback") out.rollback = rest[++i] || "";
    else if (a.startsWith("--rollback=")) out.rollback = a.slice(11);
    else if (a === "--page-size") out.pageSize = Number(rest[++i]);
    else if (a === "--help" || a === "-h") {
      console.log("See file header for usage.");
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${a}`);
    }
  }
  return out;
}

function newRunId() {
  const t = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  return `holds-${t}-${randomBytes(3).toString("hex")}`;
}

function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

async function listDelegates(db, pageSize) {
  const docs = [];
  let query = db.collectionGroup("delegates").orderBy("__name__").limit(pageSize);
  for (;;) {
    const snap = await query.get();
    if (snap.empty) break;
    docs.push(...snap.docs);
    if (snap.size < pageSize) break;
    query = db.collectionGroup("delegates").orderBy("__name__")
      .startAfter(snap.docs[snap.docs.length - 1]).limit(pageSize);
  }
  return docs;
}

function bump(map, key) {
  map[key] = (map[key] || 0) + 1;
}

async function runBackfill(db, L, args) {
  const runId = newRunId();
  const at = new Date().toISOString();
  const docs = await listDelegates(db, args.pageSize);
  const planned = [];
  const counts = {docs: docs.length, planned: 0, written: 0, skipped: 0, byReason: {}};

  for (const doc of docs) {
    const data = doc.data() || {};
    const plan = L.planBackfill(data, at, runId);
    if (plan.skip) {
      counts.skipped++;
      bump(counts.byReason, plan.reason || "skip");
      continue;
    }
    planned.push({
      path: doc.ref.path,
      uid: str(data.uid) || doc.id,
      fields: plan.fields,
      previous: plan.previous,
    });
    counts.planned++;
    if (plan.fields.holds) bump(counts.byReason, "holds");
    if (plan.fields.source) bump(counts.byReason, "source");
    if (plan.fields.rejectionReason) bump(counts.byReason, "rejectionReason");
    if (plan.fields.statusVersion) bump(counts.byReason, "statusVersion");
  }

  const report = {
    project: args.project,
    mode: args.apply ? "apply" : "dry-run",
    runId,
    at,
    counts,
  };

  const rollbackPath = args.rollback ||
    (args.apply ? path.join(process.cwd(), `delegate-holds-rollback-${runId}.json`) : "");
  if (rollbackPath) {
    const rollback = {
      project: args.project,
      runId,
      at,
      entries: planned.map((p) => ({path: p.path, uid: p.uid, previous: p.previous, fields: p.fields})),
    };
    fs.writeFileSync(rollbackPath, JSON.stringify(rollback, null, 2));
    console.log(`wrote rollback file ${rollbackPath}`);
    report.rollbackFile = rollbackPath;
  }

  if (args.apply) {
    if (PROD_PROJECTS.has(args.project) && args.allowProd !== args.project) {
      throw new Error("Refusing to apply on prod without --allow-prod-project.");
    }
    const {FieldValue} = require("firebase-admin/firestore");
    let written = 0;
    for (let i = 0; i < planned.length; i += 400) {
      const batch = db.batch();
      const slice = planned.slice(i, i + 400);
      for (const p of slice) {
        batch.update(db.doc(p.path), {
          ...p.fields,
          holdsBackfillAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      written += slice.length;
    }
    report.counts.written = written;
  }

  return {report, runId};
}

function restoreFields(previous) {
  const {FieldValue} = require("firebase-admin/firestore");
  const update = {
    holdsBackfillRunId: FieldValue.delete(),
    holdsBackfillAt: FieldValue.delete(),
  };
  for (const key of ["holds", "source", "rejectionReason", "statusVersion"]) {
    if (!Object.prototype.hasOwnProperty.call(previous || {}, key)) continue;
    update[key] = previous[key] == null ? FieldValue.delete() : previous[key];
  }
  return update;
}

async function runRevert(db, args) {
  if (!args.rollback) throw new Error("--revert requires --rollback <file>");
  const raw = JSON.parse(fs.readFileSync(args.rollback, "utf8"));
  if (raw.project && raw.project !== args.project) {
    throw new Error(`Rollback file project ${raw.project} != ${args.project}`);
  }
  const entries = raw.entries || [];
  const runId = raw.runId || "";
  if (!args.apply) {
    return {
      report: {
        project: args.project,
        mode: "revert-dry-run",
        runId,
        at: new Date().toISOString(),
        counts: {planned: entries.length, written: 0},
      },
    };
  }
  let written = 0;
  for (let i = 0; i < entries.length; i += 400) {
    const batch = db.batch();
    const slice = entries.slice(i, i + 400);
    for (const e of slice) {
      batch.update(db.doc(e.path), restoreFields(e.previous || {}));
    }
    await batch.commit();
    written += slice.length;
  }
  return {
    report: {
      project: args.project,
      mode: "revert",
      runId,
      at: new Date().toISOString(),
      counts: {planned: entries.length, written},
    },
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  if (project !== "tashil-dev" && !/^demo-/.test(project)) {
    if (!(PROD_PROJECTS.has(project) && args.allowProd === project)) {
      throw new Error(`Refusing project "${project}"`);
    }
  }
  args.project = project;

  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: project,
      serviceAccountId: project === "tashil-dev" ?
        "firebase-adminsdk-fbsvc@tashil-dev.iam.gserviceaccount.com" :
        undefined,
    });
  }
  const db = admin.firestore();
  const result = args.revert ? await runRevert(db, args) : await runBackfill(db, loadLogic(), args);
  const reportPath = args.report ||
    path.join(process.cwd(), `delegate-holds-report-${result.report.runId || "revert"}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(result.report, null, 2));
  console.log(`wrote report ${reportPath}`);
  console.log(JSON.stringify(result.report.counts, null, 2));
  console.log(`mode=${result.report.mode} runId=${result.report.runId || ""} project=${project}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = {parseArgs, restoreFields};
