/**
 * TAS-335: backfill `branchId` (and `branchOrganizationUID` when missing) on
 * attendance logs that were written without a branch id, so the branches
 * screen can find them by id instead of by name spelling.
 *
 * Matching is strict: a log is patched only when its chain
 * (branchOrganizationUID and/or organizationId) has exactly ONE branch whose
 * normalized name equals the log's branchName. Anything ambiguous or
 * unmatched goes to the report and is never written.
 *
 * Dry run is the default (read-only). Writing needs --apply and --project;
 * production also needs --allow-prod-project=practice-firebase-72df1, which
 * must only be passed after the user's written go for that run.
 *
 *   # read-only report (any project)
 *   node scripts/backfill-attendance-branch-id.js --project tashil-dev
 *   node scripts/backfill-attendance-branch-id.js --project practice-firebase-72df1 \
 *     --gcloud-account fathalla80800@gmail.com
 *   # write (tashil-dev), resumable from the cursor file
 *   node scripts/backfill-attendance-branch-id.js --project tashil-dev --apply \
 *     --backup /tmp/tas335-backup.json [--cursor /tmp/tas335-cursor.txt]
 *   # rollback a run
 *   node scripts/backfill-attendance-branch-id.js --project tashil-dev --apply \
 *     --restore /tmp/tas335-backup.json
 *
 * Options: --collection (default attendance_logs), --page-size (default 500),
 * --report <path> (default /tmp/tas335-report-<run>.json), --examples N.
 * Output has counts, chain ids, branch names and doc ids only: no people,
 * phones or device data.
 */
const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");
const {randomBytes} = require("crypto");

const PROD = "practice-firebase-72df1";
const KNOWN_PROJECTS = new Set(["tashil-dev", PROD]);
const BATCH_SIZE = 400;

/** @param {unknown} v @return {string} */
function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

/**
 * Same rules as the app's branch name normalization (branchQueryTerms /
 * normalizeBranchName): lower case, أ/إ/آ → ا, ة → ه, ى → ي, single
 * spaces; plus a leading «فرع» word is dropped.
 * @param {unknown} name
 * @return {string}
 */
function normalizeBranchName(name) {
  let s = str(name)
      .toLowerCase()
      .replace(/[أإآ]/g, "ا")
      .replace(/ة/g, "ه")
      .replace(/ى/g, "ي")
      .replace(/\s+/g, " ")
      .trim();
  s = s.replace(/^فرع\s+/, "").trim();
  return s;
}

/**
 * @param {{id: string, path: string, data: Record<string, unknown>, parentOrg: string}[]} branches
 * @return {Map<string, Map<string, {id: string, org: string, paths: string[]}[]>>}
 *   chain id → normalized name → distinct branch ids in that chain.
 */
function buildBranchIndex(branches) {
  const index = new Map();
  for (const b of branches) {
    const org = b.parentOrg || str(b.data.organizationUID) || str(b.data.organizationId);
    const key = normalizeBranchName(b.data.branchName || b.data.name || b.data.title);
    if (!org || !key || !b.id) continue;
    if (!index.has(org)) index.set(org, new Map());
    const byName = index.get(org);
    if (!byName.has(key)) byName.set(key, []);
    const list = byName.get(key);
    const same = list.find((x) => x.id === b.id);
    if (same) same.paths.push(b.path);
    else list.push({id: b.id, org, paths: [b.path]});
  }
  return index;
}

/**
 * Decides what to do with one attendance log.
 * @param {Record<string, unknown>} data
 * @param {ReturnType<typeof buildBranchIndex>} index
 * @return {{status: "has_id"|"no_name"|"no_chain"|"match"|"ambiguous"|"unmatched",
 *   patch?: Record<string, string>, candidates?: string[], chains?: string[]}}
 */
function planRecord(data, index) {
  if (str(data.branchId)) return {status: "has_id"};
  const key = normalizeBranchName(data.branchName);
  if (!key) return {status: "no_name"};
  const chains = [...new Set([str(data.branchOrganizationUID), str(data.organizationId)].filter(Boolean))];
  if (!chains.length) return {status: "no_chain"};
  const found = new Map();
  for (const c of chains) {
    for (const b of (index.get(c) && index.get(c).get(key)) || []) found.set(b.id, b);
  }
  if (found.size === 0) return {status: "unmatched", chains};
  if (found.size > 1) return {status: "ambiguous", chains, candidates: [...found.keys()].sort()};
  const [branch] = found.values();
  const patch = {branchId: branch.id};
  if (!str(data.branchOrganizationUID)) patch.branchOrganizationUID = branch.org;
  return {status: "match", patch, chains};
}

/** Previous values of the fields a patch touches (null = field was absent). */
function previousOf(data, patch) {
  const out = {};
  for (const k of Object.keys(patch)) {
    out[k] = Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null;
  }
  return out;
}

/** @param {Date|null} d @return {string} */
function dayOf(d) {
  return d ? d.toISOString().slice(0, 10) : "unknown";
}

/** @param {unknown} ts @return {Date|null} */
function toDate(ts) {
  if (ts && typeof ts.toDate === "function") return ts.toDate();
  if (ts instanceof Date) return ts;
  return null;
}

/** Fresh report accumulator. */
function newReport(meta) {
  return {
    ...meta,
    scanned: 0,
    counts: {has_id: 0, no_name: 0, no_chain: 0, match: 0, ambiguous: 0, unmatched: 0},
    missingByMonth: {},
    missingLast30DaysByDay: {},
    missingByPlatform: {},
    newestMissing: null,
    hasIdByMonth: {},
    examples: {ambiguous: [], unmatched: [], no_chain: [], no_name: []},
    written: 0,
    skipped: {},
  };
}

/**
 * Adds one record's outcome to the report. Examples keep doc id, chain ids
 * and the branch name only.
 */
function tally(report, docId, data, plan, maxExamples, now = new Date()) {
  report.scanned++;
  report.counts[plan.status]++;
  const d = toDate(data.timestamp);
  const month = d ? d.toISOString().slice(0, 7) : "unknown";
  if (plan.status === "has_id") {
    report.hasIdByMonth[month] = (report.hasIdByMonth[month] || 0) + 1;
    return;
  }
  report.missingByMonth[month] = (report.missingByMonth[month] || 0) + 1;
  if (d && now - d <= 30 * 86400000) {
    const day = dayOf(d);
    report.missingLast30DaysByDay[day] = (report.missingLast30DaysByDay[day] || 0) + 1;
  }
  const info = str(data.deviceInfo).toLowerCase();
  const platform = !info ? "none" : (/iphone|ios|ipad/.test(info) ? "ios" : "android");
  report.missingByPlatform[platform] = (report.missingByPlatform[platform] || 0) + 1;
  if (d && (!report.newestMissing || d.toISOString() > report.newestMissing)) {
    report.newestMissing = d.toISOString();
  }
  const bucket = report.examples[plan.status];
  if (bucket && bucket.length < maxExamples) {
    bucket.push({
      doc: docId,
      day: dayOf(d),
      branchName: str(data.branchName),
      chains: plan.chains || [],
      ...(plan.candidates ? {candidates: plan.candidates} : {}),
    });
  }
}

/** @param {string[]} argv */
function parseArgs(argv) {
  const out = {
    project: "", apply: false, allowProd: "", gcloudAccount: "", backup: "", restore: "",
    cursor: "", report: "", collection: "attendance_logs", pageSize: 500, examples: 15,
  };
  const val = (i) => {
    if (i >= argv.length) throw new Error(`Missing value for ${argv[i - 1]}`);
    return argv[i];
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--apply") out.apply = true;
    else if (a === "--dry-run") out.apply = false;
    else if (a.startsWith("--allow-prod-project=")) out.allowProd = a.slice(21).trim();
    else if (a === "--project") out.project = val(++i).trim().toLowerCase();
    else if (a === "--gcloud-account") out.gcloudAccount = val(++i).trim();
    else if (a === "--backup") out.backup = val(++i);
    else if (a === "--restore") out.restore = val(++i);
    else if (a === "--cursor") out.cursor = val(++i);
    else if (a === "--report") out.report = val(++i);
    else if (a === "--collection") out.collection = val(++i);
    else if (a === "--page-size") out.pageSize = Math.max(1, Math.min(1000, Number(val(++i)) || 500));
    else if (a === "--examples") out.examples = Math.max(0, Number(val(++i)) || 0);
    else throw new Error(`Unknown option ${a}`);
  }
  if (!out.project) throw new Error("--project is required (no default project).");
  if (!KNOWN_PROJECTS.has(out.project)) throw new Error(`Refusing unknown project "${out.project}".`);
  if (!["attendance_logs", "attendance_logs_testing"].includes(out.collection)) {
    throw new Error(`Refusing collection "${out.collection}".`);
  }
  if (out.apply) {
    if (out.project === PROD && out.allowProd !== PROD) {
      throw new Error(`--apply on ${PROD} needs --allow-prod-project=${PROD} (user's written go).`);
    }
    if (!out.restore && !out.backup) throw new Error("--apply needs --backup <new file>.");
  }
  return out;
}

function initDb(args) {
  if (args.gcloudAccount) {
    // Read with a named gcloud account (e.g. production dry run) instead of ADC.
    const {Firestore} = require("@google-cloud/firestore");
    const {OAuth2Client} = require("google-auth-library");
    const authClient = new OAuth2Client();
    authClient.setCredentials({
      access_token: execFileSync("gcloud",
          ["auth", "print-access-token", `--account=${args.gcloudAccount}`]).toString().trim(),
    });
    return new Firestore({projectId: args.project, authClient});
  }
  const admin = require("firebase-admin");
  admin.initializeApp({projectId: args.project});
  return admin.firestore();
}

/** Loads every branch doc: root `branches` and `organizations/{org}/branches`. */
async function loadBranches(db) {
  const snap = await db.collectionGroup("branches").get();
  return snap.docs.map((d) => {
    const parent = d.ref.parent.parent;
    const parentOrg = parent && parent.parent && parent.parent.id === "organizations" ? parent.id : "";
    return {id: d.id, path: d.ref.path, data: d.data(), parentOrg};
  });
}

/** Commits a batch with lastUpdateTime preconditions; per-doc retry on failure. */
async function writeRows(db, rows, report) {
  if (!rows.length) return;
  const batch = db.batch();
  for (const r of rows) batch.update(db.doc(r.path), r.patch, {lastUpdateTime: r.updateTime});
  try {
    await batch.commit();
    report.written += rows.length;
    return;
  } catch (e) {
    // One changed doc fails the whole batch: retry one by one.
  }
  for (const r of rows) {
    try {
      await db.doc(r.path).update(r.patch, {lastUpdateTime: r.updateTime});
      report.written++;
    } catch (e) {
      const reason = /precondition|FAILED_PRECONDITION|9 /i.test(String(e && e.message)) ?
        "changed_since_read" : "write_error";
      report.skipped[reason] = (report.skipped[reason] || 0) + 1;
    }
  }
}

function appendBackup(file, entries) {
  // One JSON object per line, so a resumed run keeps appending.
  if (!entries.length) return;
  fs.appendFileSync(file, entries.map((e) => JSON.stringify(e)).join("\n") + "\n");
}

async function runScan(db, args) {
  const runId = `tas335-${new Date().toISOString().replace(/[-:.]/g, "")}-${randomBytes(2).toString("hex")}`;
  const report = newReport({
    runId, project: args.project, collection: args.collection,
    mode: args.apply ? "apply" : "dry-run", startedAt: new Date().toISOString(),
  });
  const branches = await loadBranches(db);
  const index = buildBranchIndex(branches);
  report.branchDocs = branches.length;
  report.chains = index.size;

  let startAfter = "";
  if (args.cursor && fs.existsSync(args.cursor)) startAfter = fs.readFileSync(args.cursor, "utf8").trim();
  if (startAfter) report.resumedAfter = startAfter;
  if (args.apply && fs.existsSync(args.backup) && !startAfter) {
    throw new Error(`Backup ${args.backup} exists: pass --cursor to resume, or use a new file.`);
  }

  const col = db.collection(args.collection);
  for (;;) {
    let q = col.orderBy("__name__").limit(args.pageSize)
        .select("branchId", "branchName", "organizationId", "branchOrganizationUID", "timestamp", "deviceInfo");
    if (startAfter) q = q.startAfter(col.doc(startAfter));
    const page = await q.get();
    if (page.empty) break;
    const rows = [];
    for (const d of page.docs) {
      const data = d.data();
      const plan = planRecord(data, index);
      tally(report, d.id, data, plan, args.examples);
      if (plan.status === "match") {
        rows.push({path: d.ref.path, patch: plan.patch, previous: previousOf(data, plan.patch), updateTime: d.updateTime});
      }
    }
    if (args.apply) {
      for (let i = 0; i < rows.length; i += BATCH_SIZE) {
        const chunk = rows.slice(i, i + BATCH_SIZE);
        appendBackup(args.backup, chunk.map((r) => ({path: r.path, previous: r.previous, written: r.patch})));
        await writeRows(db, chunk, report);
      }
    }
    startAfter = page.docs[page.docs.length - 1].id;
    if (args.cursor) fs.writeFileSync(args.cursor, startAfter);
    if (page.size < args.pageSize) break;
  }
  report.finishedAt = new Date().toISOString();
  return report;
}

/** Puts back the previous values of every field this backfill wrote. */
async function runRestore(db, args) {
  const {FieldValue} = require("@google-cloud/firestore");
  const lines = fs.readFileSync(args.restore, "utf8").split("\n").filter(Boolean);
  const report = {project: args.project, mode: args.apply ? "restore-apply" : "restore-dry-run",
    entries: lines.length, restorable: 0, restored: 0, skipped: {}};
  for (const line of lines) {
    const e = JSON.parse(line);
    const snap = await db.doc(e.path).get();
    const cur = snap.exists ? snap.data() : null;
    const still = cur && Object.keys(e.written).every((k) => cur[k] === e.written[k]);
    if (!still) {
      report.skipped.changed_after_backfill = (report.skipped.changed_after_backfill || 0) + 1;
      continue;
    }
    const patch = {};
    for (const [k, v] of Object.entries(e.previous)) {
      patch[k] = v === null ? FieldValue.delete() : v;
    }
    report.restorable++;
    if (args.apply) {
      await db.doc(e.path).update(patch, {lastUpdateTime: snap.updateTime});
      report.restored++;
    }
  }
  return report;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const db = initDb(args);
  const report = args.restore ? await runRestore(db, args) : await runScan(db, args);
  const reportPath = args.report || path.join("/tmp", `${report.runId || "tas335-restore"}-report.json`);
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  const summary = {...report};
  delete summary.examples;
  console.log(JSON.stringify(summary, null, 2));
  console.log(`report: ${reportPath}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e && e.message ? e.message : e);
    process.exit(1);
  });
}

module.exports = {normalizeBranchName, buildBranchIndex, planRecord, previousOf, tally, newReport, parseArgs};
