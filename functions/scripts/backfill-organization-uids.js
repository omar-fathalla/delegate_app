/**
 * Backfill organizationUIDs (and organizationNames) on existing
 * delegate_requests that only have the singular organizationUID.
 *
 * Dry-run is the default. Pass --apply to write. Always pass --project.
 *
 *   node scripts/backfill-organization-uids.js --project tashil-dev --rollback /tmp/org-uids-rollback.json
 *   node scripts/backfill-organization-uids.js --project tashil-dev --apply --rollback /tmp/org-uids-rollback.json
 *
 * tashil-dev only unless a later written go passes --allow-prod-project.
 * Does not deploy anything. Counts only in stdout; no personal data.
 */
const fs = require("fs");
const path = require("path");
const {parseArgs, assertTarget} = require("./p0-common");

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
    planned.push({path: doc.ref.path, id: doc.id, patch, previous: previousOf(data)});
  }

  const runId = `org-uids-${new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z")}`;
  const report = {
    project: args.project,
    mode: args.apply ? "apply" : "dry-run",
    runId,
    at: new Date().toISOString(),
    counts: {docs: snap.size, planned: planned.length, skipped, written: 0},
  };

  const rollbackPath = args.rollback ||
    path.join("/tmp", `organization-uids-rollback-${runId}.json`);
  const rollback = {
    project: args.project,
    runId,
    at: report.at,
    entries: planned.map((p) => ({path: p.path, previous: p.previous})),
  };
  fs.writeFileSync(rollbackPath, JSON.stringify(rollback, null, 2));
  report.rollbackFile = rollbackPath;
  console.log(`wrote rollback file ${rollbackPath} (${planned.length} entries)`);

  if (!args.apply) {
    return report;
  }

  let written = 0;
  for (let i = 0; i < planned.length; i += 400) {
    const batch = db.batch();
    const slice = planned.slice(i, i + 400);
    for (const p of slice) {
      batch.update(db.doc(p.path), p.patch);
    }
    await batch.commit();
    written += slice.length;
  }
  report.counts.written = written;
  return report;
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2));
  const project = assertTarget(parsed);
  parsed.project = project;
  parsed.rollback = "";
  const rest = parsed.rest || [];
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--rollback") parsed.rollback = rest[++i] || "";
    else if (a.startsWith("--rollback=")) parsed.rollback = a.slice(11);
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
  const report = await run(admin.firestore(), parsed);
  const reportPath = path.join(
    "/tmp",
    `organization-uids-report-${report.runId}.json`,
  );
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`wrote report ${reportPath}`);
  console.log(JSON.stringify(report.counts, null, 2));
  console.log(`mode=${report.mode} runId=${report.runId} project=${project}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = {planPatch, previousOf, run};
