/**
 * Backfill organizationUIDs (and organizationNames) on existing
 * delegate_requests that only have the singular organizationUID.
 *
 * Dry-run is the default. Pass --dry-run explicitly or omit --apply. Pass
 * --apply to write. Always pass --project. See README-organization-uids-backfill.md
 * for Mohamed run order (dry-run tashil-dev first, then --apply tashil-dev only;
 * never prod).
 *
 *   node scripts/backfill-organization-uids.js --project tashil-dev --dry-run --rollback /tmp/org-uids-rollback.json
 *   node scripts/backfill-organization-uids.js --project tashil-dev --apply --rollback /tmp/org-uids-rollback.json
 *   node scripts/backfill-organization-uids.js --project tashil-dev --dry-run --restore /tmp/org-uids-rollback.json
 *   node scripts/backfill-organization-uids.js --project tashil-dev --apply --restore /tmp/org-uids-rollback.json
 *
 * tashil-dev only unless a later written go passes --allow-prod-project.
 * Does not deploy anything. Counts only in stdout; no personal data.
 */
const fs = require("fs");
const path = require("path");
const {
  parseArgs, assertTarget, newBackfillRunId, writeJsonFileNew, writeJsonFilePartial,
} = require("./p0-common");

function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

/** Returns the patch, or null if the doc should be left alone. */
function planPatch(data) {
  const uid = str(data.organizationUID);
  if (!uid) return null;
  const existing = data.organizationUIDs;
  if (Array.isArray(existing) && existing.some((e) => str(e) !== "")) return null;
  const patch = {organizationUIDs: [uid]};
  const name = str(data.organizationName);
  const existingNames = data.organizationNames;
  const hasNames = Array.isArray(existingNames) && existingNames.some((e) => str(e) !== "");
  if (name && !hasNames) patch.organizationNames = [name];
  return patch;
}

function previousOf(data) {
  return {
    organizationUIDs: Object.prototype.hasOwnProperty.call(data, "organizationUIDs")
      ? data.organizationUIDs : null,
    organizationNames: Object.prototype.hasOwnProperty.call(data, "organizationNames")
      ? data.organizationNames : null,
  };
}

/** Build the write that puts a doc back to its pre-backfill fields. */
function planRestore(previous) {
  const admin = require("firebase-admin");
  const patch = {};
  if (!previous || previous.organizationUIDs === null || previous.organizationUIDs === undefined) {
    patch.organizationUIDs = admin.firestore.FieldValue.delete();
  } else {
    patch.organizationUIDs = previous.organizationUIDs;
  }
  if (!previous || previous.organizationNames === null || previous.organizationNames === undefined) {
    patch.organizationNames = admin.firestore.FieldValue.delete();
  } else {
    patch.organizationNames = previous.organizationNames;
  }
  return patch;
}

function isDeleteSentinel(value) {
  return !!(value && typeof value === "object" && typeof value.isEqual === "function" &&
    value.isEqual(require("firebase-admin").firestore.FieldValue.delete()));
}

function valuesEqual(a, b) {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
}

/** Fields consulted by planPatch; captured at scan time for --apply guards. */
function atReadOf(data) {
  const d = data || {};
  return {
    organizationUID: d.organizationUID,
    organizationName: d.organizationName,
    organizationUIDs: d.organizationUIDs,
    organizationNames: d.organizationNames,
  };
}

function changedSinceRead(live, atRead) {
  return !valuesEqual(atReadOf(live), atRead);
}

/** Skip apply when the doc changed after the initial collection scan. */
function shouldApplyWrite(live, planned) {
  if (changedSinceRead(live, planned.atRead)) {
    return {ok: false, reason: "changed_since_read"};
  }
  const patch = planPatch(live || {});
  if (!patch || !valuesEqual(patch, planned.patch)) {
    return {ok: false, reason: "plan_changed"};
  }
  return {ok: true};
}

/**
 * The fields the backfill wrote. Prefer `entry.fields` when the rollback
 * file has them; otherwise reconstruct from the pre-backfill `previous`
 * and the live singular organizationUID / organizationName.
 */
function writtenFieldsOf(entry, current) {
  if (entry && entry.fields && typeof entry.fields === "object" &&
      Object.keys(entry.fields).length > 0) {
    return entry.fields;
  }
  const previous = (entry && entry.previous) || {};
  return planPatch({
    organizationUID: current && current.organizationUID,
    organizationName: current && current.organizationName,
    organizationUIDs: previous.organizationUIDs,
    organizationNames: previous.organizationNames,
  });
}

function currentMatchesWritten(data, written) {
  if (!written || typeof written !== "object") return false;
  const keys = Object.keys(written).filter((k) => !isDeleteSentinel(written[k]));
  if (keys.length === 0) return false;
  return keys.every((k) => valuesEqual(data ? data[k] : undefined, written[k]));
}

/** Refuse after scan when any planned row is not a safe delegate_requests patch. */
function assertValidBackfillPlan(planned) {
  for (const p of planned) {
    if (!p || typeof p.path !== "string" || !p.path.startsWith("delegate_requests/")) {
      throw new Error(`Invalid backfill plan: bad path ${p && p.path}`);
    }
    if (!p.patch || typeof p.patch !== "object" || !Object.keys(p.patch).length) {
      throw new Error(`Invalid backfill plan: empty patch for ${p.path}`);
    }
  }
}

/** @param {unknown} err */
function isPreconditionFailure(err) {
  const code = err && (err.code || err.status);
  if (code === 9 || code === "failed-precondition" || code === "FAILED_PRECONDITION") return true;
  const msg = String((err && err.message) || err || "");
  return /precondition|last update time|ABORTED/i.test(msg);
}

/**
 * Applies patches using Firestore lastUpdateTime preconditions (one failed
 * precondition skips that doc; other errors propagate).
 * @param {FirebaseFirestore.Firestore} db
 * @param {{path: string, patch: object, lastUpdateTime: FirebaseFirestore.Timestamp}[]} rows
 */
async function writePatchesWithPrecondition(db, rows) {
  let written = 0;
  const skipReasons = {};
  for (const row of rows) {
    if (!row.lastUpdateTime) {
      skipReasons.missing_update_time = (skipReasons.missing_update_time || 0) + 1;
      continue;
    }
    try {
      await db.doc(row.path).update(row.patch, {lastUpdateTime: row.lastUpdateTime});
      written++;
    } catch (e) {
      if (isPreconditionFailure(e)) {
        skipReasons.precondition_failed = (skipReasons.precondition_failed || 0) + 1;
        continue;
      }
      const err = e instanceof Error ? e : new Error(String(e));
      err.partialWritten = written;
      err.partialSkipReasons = skipReasons;
      throw err;
    }
  }
  return {written, skipReasons};
}

function reportPathFor(runId) {
  return path.join("/tmp", `organization-uids-report-${runId}.json`);
}

function persistReport(report, partial = false) {
  const reportPath = reportPathFor(report.runId);
  if (partial) {
    writeJsonFilePartial(reportPath, report);
  } else {
    writeJsonFileNew(reportPath, report, "report");
  }
  console.log(`wrote ${partial ? "partial " : ""}report ${reportPath}`);
  return reportPath;
}

/** Restore only when the doc still holds the backfill's written value. */
function shouldRestore(data, entry) {
  const written = writtenFieldsOf(entry, data || {});
  if (!written) return {ok: false, reason: "cannot_reconstruct_written"};
  if (!currentMatchesWritten(data || {}, written)) {
    return {ok: false, reason: "current_differs_from_written"};
  }
  return {ok: true, written};
}

async function restore(db, args) {
  const restorePath = args.restore;
  if (!restorePath) throw new Error("--restore requires a rollback JSON file");
  const raw = JSON.parse(fs.readFileSync(restorePath, "utf8"));
  if (raw.project && raw.project !== args.project) {
    throw new Error(`rollback file project ${raw.project} does not match --project ${args.project}`);
  }
  const entries = Array.isArray(raw.entries) ? raw.entries : [];
  const candidates = entries
    .filter((e) => e && typeof e.path === "string" && e.path.startsWith("delegate_requests/"))
    .map((e) => ({path: e.path, id: e.path.split("/")[1], patch: planRestore(e.previous), previous: e.previous, fields: e.fields, entry: e}));

  const planned = [];
  let skipped = 0;
  const skipReasons = {};
  for (const c of candidates) {
    const snap = await db.doc(c.path).get();
    const data = snap.exists ? (snap.data() || {}) : null;
    const decision = shouldRestore(data, c.entry);
    if (!decision.ok) {
      skipped++;
      skipReasons[decision.reason] = (skipReasons[decision.reason] || 0) + 1;
      continue;
    }
    planned.push({...c, lastUpdateTime: snap.updateTime});
  }

  const runId = newBackfillRunId("org-uids-restore");
  const report = {
    project: args.project,
    mode: args.apply ? "restore-apply" : "restore-dry-run",
    runId,
    at: new Date().toISOString(),
    rollbackFile: restorePath,
    counts: {docs: candidates.length, planned: planned.length, skipped, written: 0, skipReasons},
  };
  if (!args.apply) return report;

  try {
    const {written, skipReasons: preconditionSkips} = await writePatchesWithPrecondition(db, planned);
    report.counts.written = written;
    if (Object.keys(preconditionSkips).length) {
      report.counts.applySkipReasons = {...(report.counts.skipReasons || {}), ...preconditionSkips};
      report.counts.applySkipped = Object.values(preconditionSkips).reduce((a, b) => a + b, 0);
    }
    return report;
  } catch (e) {
    report.partial = true;
    report.error = e.message || String(e);
    report.counts.written = typeof e.partialWritten === "number" ? e.partialWritten : report.counts.written;
    if (e.partialSkipReasons) {
      report.counts.applySkipReasons = {...(report.counts.applySkipReasons || {}), ...e.partialSkipReasons};
    }
    persistReport(report, true);
    throw e;
  }
}

async function run(db, args) {
  const snap = await db.collection("delegate_requests").get();
  const planned = [];
  let skipped = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const patch = planPatch(data);
    if (!patch) {
      skipped++;
      continue;
    }
    planned.push({
      path: doc.ref.path,
      id: doc.id,
      patch,
      previous: previousOf(data),
      atRead: atReadOf(data),
    });
  }

  assertValidBackfillPlan(planned);

  const runId = newBackfillRunId("org-uids");
  const report = {
    project: args.project,
    mode: args.apply ? "apply" : "dry-run",
    runId,
    at: new Date().toISOString(),
    counts: {docs: snap.size, planned: planned.length, skipped, written: 0, applySkipped: 0, applySkipReasons: {}},
  };

  const rollbackPath = args.rollback ||
    path.join("/tmp", `organization-uids-rollback-${runId}.json`);
  const rollback = {
    project: args.project,
    runId,
    at: report.at,
    entries: planned.map((p) => ({path: p.path, previous: p.previous, fields: p.patch})),
  };
  writeJsonFileNew(rollbackPath, rollback, "rollback");
  report.rollbackFile = rollbackPath;
  console.log(`wrote rollback file ${rollbackPath} (${planned.length} entries)`);

  if (!args.apply) {
    return report;
  }

  const toWrite = [];
  const applySkipReasons = {};
  for (const p of planned) {
    const snap = await db.doc(p.path).get();
    const data = snap.exists ? (snap.data() || {}) : null;
    const decision = shouldApplyWrite(data, p);
    if (!decision.ok) {
      report.counts.applySkipped++;
      applySkipReasons[decision.reason] = (applySkipReasons[decision.reason] || 0) + 1;
      continue;
    }
    toWrite.push({...p, lastUpdateTime: snap.updateTime});
  }
  report.counts.applySkipReasons = applySkipReasons;

  const rows = toWrite.map((p) => ({
    path: p.path,
    patch: p.patch,
    lastUpdateTime: p.lastUpdateTime,
  }));
  try {
    const {written, skipReasons: preconditionSkips} = await writePatchesWithPrecondition(db, rows);
    for (const [reason, n] of Object.entries(preconditionSkips)) {
      report.counts.applySkipped += n;
      applySkipReasons[reason] = (applySkipReasons[reason] || 0) + n;
    }
    report.counts.applySkipReasons = applySkipReasons;
    report.counts.written = written;
    return report;
  } catch (e) {
    report.partial = true;
    report.error = e.message || String(e);
    report.counts.written = typeof e.partialWritten === "number" ? e.partialWritten : report.counts.written;
    if (e.partialSkipReasons) {
      report.counts.applySkipReasons = {...(report.counts.applySkipReasons || {}), ...e.partialSkipReasons};
    }
    persistReport(report, true);
    throw e;
  }
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2));
  const project = assertTarget(parsed);
  parsed.project = project;
  parsed.rollback = "";
  parsed.restore = "";
  const rest = parsed.rest || [];
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--rollback") parsed.rollback = rest[++i] || "";
    else if (a.startsWith("--rollback=")) parsed.rollback = a.slice(11);
    else if (a === "--restore") parsed.restore = rest[++i] || "";
    else if (a.startsWith("--restore=")) parsed.restore = a.slice(10);
    else if (a === "--help" || a === "-h") {
      console.log("See file header for usage.");
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${a}`);
    }
  }

  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: project,
      serviceAccountId: project === "tashil-dev"
        ? "firebase-adminsdk-fbsvc@tashil-dev.iam.gserviceaccount.com"
        : undefined,
    });
  }
  const report = parsed.restore
    ? await restore(admin.firestore(), parsed)
    : await run(admin.firestore(), parsed);
  persistReport(report, false);
  console.log(JSON.stringify(report.counts, null, 2));
  console.log(`mode=${report.mode} runId=${report.runId} project=${project}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = {
  planPatch, previousOf, planRestore, restore, run, writtenFieldsOf, currentMatchesWritten,
  shouldRestore, isDeleteSentinel, atReadOf, changedSinceRead, shouldApplyWrite,
  assertValidBackfillPlan, isPreconditionFailure, writePatchesWithPrecondition,
};
