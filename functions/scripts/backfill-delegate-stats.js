/**
 * TAS-87: recompute the delegate stats docs from scratch.
 *
 *   organizations/{orgId}/stats/delegates
 *   organizations/{orgId}/companies/{companyId}/stats/delegates
 *
 * Dry-run by default: reads every delegate doc once, prints counts only
 * (no names, phones or IDs), and says how many stats docs are missing or
 * differ from a fresh recompute. After the trigger is live a dry-run that
 * prints `differ: 0` is the health check.
 *
 * It also compares against the OLD web computation (delegates matched by the
 * organizationUID / companyUID fields through a collection-group read) and
 * prints how many orgs / companies would show different numbers.
 *
 *   npm run build   # loads lib/delegate_stats_logic
 *   node scripts/backfill-delegate-stats.js --project tashil-dev
 *   node scripts/backfill-delegate-stats.js --project tashil-dev --apply
 *   node scripts/backfill-delegate-stats.js --project tashil-dev --report ./stats-report.json
 *
 * --project is required. Only tashil-dev and demo-* (emulator) run; the
 * production project needs --allow-prod-project=practice-firebase-72df1,
 * which only a later, explicit go from the user allows.
 * --apply replaces the counted fields of each doc (set without merge). A
 * delegate write that lands between the read and the write can be lost; run
 * it when nobody is editing, and a second dry-run shows any drift.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const {parseArgs: parseCommonArgs, assertTarget} = require("./p0-common");

function loadLogic() {
  const compiled = path.join(__dirname, "../lib/delegate_stats_logic.js");
  if (!fs.existsSync(compiled)) {
    throw new Error("Missing functions/lib/delegate_stats_logic.js — run npm run build in functions/ first.");
  }
  return require("../lib/delegate_stats_logic");
}

function parseArgs(argv) {
  const common = parseCommonArgs(argv);
  const out = {project: common.project, apply: common.apply, allowProd: common.allowProd, report: "", pageSize: 500};
  const rest = common.rest;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--report") out.report = rest[++i] || "";
    else if (a.startsWith("--report=")) out.report = a.slice(9);
    else if (a === "--page-size") out.pageSize = Number(rest[++i]);
    else if (a === "--help" || a === "-h") {
      console.log("See file header for usage.");
      process.exit(0);
    } else throw new Error(`Unknown argument: ${a}`);
  }
  if (!Number.isInteger(out.pageSize) || out.pageSize < 1 || out.pageSize > 1000) {
    throw new Error("--page-size must be 1..1000");
  }
  return out;
}

const orgPath = (o) => `organizations/${o}/stats/delegates`;
const coPath = (o, c) => `organizations/${o}/companies/${c}/stats/delegates`;

/**
 * Reads everything and computes the fresh stats.
 * @return {Promise<{orgs: Map, companies: Map, oldOrgs: Map, oldCompanies: Map, scanned: number, skipped: number}>}
 */
async function computeAll(db, L, pageSize) {
  const orgs = new Map(); // orgId -> StatsDoc (path based, what the trigger keeps)
  const companies = new Map(); // "o/c" -> {orgId, companyId, stats}
  const oldOrgs = new Map(); // organizationUID field -> StatsDoc (old web read)
  const oldCompanies = new Map(); // "o/c" by fields

  const orgDoc = (m, o) => m.get(o) || m.set(o, L.emptyStats(true)).get(o);
  const coDoc = (m, o, c) => {
    const k = `${o}/${c}`;
    return (m.get(k) || m.set(k, {orgId: o, companyId: c, stats: L.emptyStats(false)}).get(k)).stats;
  };

  for (const o of await db.collection("organizations").listDocuments()) orgDoc(orgs, o.id);
  const cos = await db.collectionGroup("companies").select().get();
  for (const c of cos.docs) {
    const p = c.ref.path.split("/");
    if (p.length === 4 && p[0] === "organizations") {
      orgDoc(orgs, p[1]);
      coDoc(companies, p[1], p[3]);
    }
  }

  let scanned = 0;
  let skipped = 0;
  let last = null;
  const {FieldPath} = require("firebase-admin").firestore;
  for (;;) {
    let q = db.collectionGroup("delegates")
      .select("status", "city", "position", "documents", "organizationUID", "companyUID")
      .orderBy(FieldPath.documentId())
      .limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      scanned++;
      const data = doc.data();
      const loc = L.parseDelegatePath(doc.ref.path);
      if (loc) {
        L.accumulate(orgDoc(orgs, loc.orgId), data, loc.companyId);
        L.accumulate(coDoc(companies, loc.orgId, loc.companyId), data, null);
      } else skipped++;
      const fo = typeof data.organizationUID === "string" ? data.organizationUID : "";
      const fc = typeof data.companyUID === "string" ? data.companyUID : "";
      if (fo) {
        L.accumulate(orgDoc(oldOrgs, fo), data, fc || "(none)");
        if (fc) L.accumulate(coDoc(oldCompanies, fo, fc), data, null);
      }
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return {orgs, companies, oldOrgs, oldCompanies, scanned, skipped};
}

/** Fields the old web screens show, so the comparison ignores byCompany keys of "(none)". */
function shown(stats) {
  return {total: stats.total, active: stats.active, s1InsuranceDocs: stats.s1InsuranceDocs,
    embassyHealthCerts: stats.embassyHealthCerts, byCity: stats.byCity};
}

async function run(db, L, args, log = console.log) {
  const all = await computeAll(db, L, args.pageSize);
  const targets = [];
  for (const [o, stats] of all.orgs) targets.push({path: orgPath(o), stats, extra: {orgId: o}});
  for (const {orgId, companyId, stats} of all.companies.values()) {
    targets.push({path: coPath(orgId, companyId), stats, extra: {orgId, companyId}});
  }

  let missing = 0;
  let differ = 0;
  for (let i = 0; i < targets.length; i += 300) {
    const chunk = targets.slice(i, i + 300);
    const snaps = await db.getAll(...chunk.map((t) => db.doc(t.path)));
    snaps.forEach((s, j) => {
      chunk[j].existing = s.exists ? s.data() : null;
      if (!s.exists) missing++;
      else if (!L.sameStats(s.data(), chunk[j].stats)) differ++;
    });
  }

  // Old web computation vs path based (what the dashboards will now show).
  let oldOrgDiff = 0;
  for (const [o, stats] of all.orgs) {
    if (!L.sameStats(shown(stats), shown(all.oldOrgs.get(o) || L.emptyStats(true)))) oldOrgDiff++;
  }
  for (const o of all.oldOrgs.keys()) if (!all.orgs.has(o)) oldOrgDiff++;
  let oldCoDiff = 0;
  for (const [k, v] of all.companies) {
    const old = all.oldCompanies.get(k);
    if (!L.sameStats(v.stats, old ? old.stats : L.emptyStats(false))) oldCoDiff++;
  }
  for (const k of all.oldCompanies.keys()) if (!all.companies.has(k)) oldCoDiff++;

  const summary = {
    project: args.project,
    mode: args.apply ? "apply" : "dry-run",
    delegatesScanned: all.scanned,
    delegatesNotNested: all.skipped,
    orgDocs: all.orgs.size,
    companyDocs: all.companies.size,
    missing,
    differ,
    oldWebOrgsDifferent: oldOrgDiff,
    oldWebCompaniesDifferent: oldCoDiff,
    written: 0,
  };

  if (args.apply) {
    const admin = require("firebase-admin");
    const now = admin.firestore.FieldValue.serverTimestamp();
    const writer = db.bulkWriter();
    for (const t of targets) {
      if (t.existing && L.sameStats(t.existing, t.stats)) continue;
      writer.set(db.doc(t.path), {
        ...t.stats,
        ...t.extra,
        schemaVersion: L.STATS_SCHEMA_VERSION,
        updatedAt: now,
        backfilledAt: now,
      });
      summary.written++;
    }
    await writer.close();
  }

  log(JSON.stringify(summary, null, 2));
  if (args.report) {
    const detail = {
      summary,
      orgs: [...all.orgs].map(([o, s]) => ({orgId: o, stats: s})),
      companies: [...all.companies.values()],
    };
    fs.writeFileSync(args.report, JSON.stringify(detail, null, 2));
    log(`report: ${args.report}`);
  }
  return summary;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  const L = loadLogic();
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: project});
  await run(admin.firestore(), L, {...args, project});
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e && e.message ? e.message : e);
    process.exit(1);
  });
}

module.exports = {parseArgs, run, computeAll};
