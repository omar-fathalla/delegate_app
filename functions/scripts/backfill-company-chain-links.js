/**
 * Backfill automatic chain links (Mohamed, 17 Nov 2026): every eligible
 * delegate gets a copy in every chain their company is in. Same rules as
 * the functions (lib/company_chain_autolink): free chains (فتح الله, from
 * config/subscriptions.freeChainOrgUids or org.subscriptionExempt) for any
 * active delegate; paid chains only with paid coverage.
 *
 * Dry run by default; prints counts only (no names, phones, national IDs).
 *
 *   node scripts/backfill-company-chain-links.js --project tashil-dev
 *   node scripts/backfill-company-chain-links.js --project tashil-dev --apply
 *   node scripts/backfill-company-chain-links.js --project tashil-dev --now 2027-01-20
 *   node scripts/backfill-company-chain-links.js --project practice-firebase-72df1 --read-only-prod
 *
 *   # prod, one company only (Mohamed's go t1498u for smotchi):
 *   node scripts/backfill-company-chain-links.js --project practice-firebase-72df1 \
 *     --company WB076VvAgAsKMIQAZV8g --apply --allow-prod-project=practice-firebase-72df1 \
 *     --rollback ./smotchi-rollback.json
 *   node scripts/backfill-company-chain-links.js --project practice-firebase-72df1 \
 *     --allow-prod-project=practice-firebase-72df1 --revert ./smotchi-rollback.json
 *
 * --apply on prod needs --company, --allow-prod-project=<prod id> and
 * --rollback <file>. The rollback file lists every doc created or changed
 * with its before-state; --revert deletes the docs this run created and
 * restores the changed fields.
 * Requires `npm run build` in functions/ first.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const {PROD_PROJECTS, normalizeProject} = require("./p0-common");

function parseArgs(argv) {
  const out = {project: "", apply: false, readOnlyProd: false, now: null, company: "", report: "",
    allowProd: "", rollback: "", revert: ""};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--apply") out.apply = true;
    else if (a === "--dry-run") out.apply = false;
    else if (a === "--read-only-prod") out.readOnlyProd = true;
    else if (a === "--project") out.project = normalizeProject(argv[++i]);
    else if (a.startsWith("--project=")) out.project = normalizeProject(a.slice(10));
    else if (a === "--now") out.now = new Date(argv[++i]);
    else if (a === "--company") out.company = String(argv[++i] || "").trim();
    else if (a === "--report") out.report = argv[++i] || "";
    else if (a.startsWith("--allow-prod-project=")) out.allowProd = normalizeProject(a.slice(21));
    else if (a === "--rollback") out.rollback = argv[++i] || "";
    else if (a === "--revert") out.revert = argv[++i] || "";
    else if (a === "--help" || a === "-h") {
      console.log("See file header for usage.");
      process.exit(0);
    } else throw new Error(`Unknown argument: ${a}`);
  }
  if (out.now && isNaN(out.now.getTime())) throw new Error("--now must be a date (YYYY-MM-DD)");
  return out;
}

function assertSafe(args) {
  const p = args.project;
  if (!p) throw new Error("--project is required (no default project).");
  const devLike = p === "tashil-dev" || /^demo-[a-z0-9-]{1,40}$/.test(p);
  if (PROD_PROJECTS.has(p)) {
    if (args.apply || args.revert) {
      if (args.allowProd !== p) throw new Error("Prod writes need --allow-prod-project=<the same prod id>.");
      if (args.revert) return p;
      if (!args.company) throw new Error("Prod --apply needs --company (one company only).");
      if (!args.rollback) throw new Error("Prod --apply needs --rollback <file>.");
      if (args.now) throw new Error("--now is for dry runs only.");
      return p;
    }
    if (!args.readOnlyProd) throw new Error("Prod dry run needs --read-only-prod.");
    return p;
  }
  if (!devLike) throw new Error(`Refusing project "${p}": only tashil-dev, demo-*, or a prod read-only dry run.`);
  if (args.apply && args.now) throw new Error("--now is for dry runs only.");
  return p;
}

function toJson(v) {
  if (v && typeof v.toDate === "function") return {__ts: v.toDate().toISOString()};
  if (Array.isArray(v)) return v.map(toJson);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toJson(x)]));
  return v;
}

function fromJson(admin, v) {
  if (v && typeof v === "object" && !Array.isArray(v) && v.__ts) return admin.firestore.Timestamp.fromDate(new Date(v.__ts));
  if (Array.isArray(v)) return v.map((x) => fromJson(admin, x));
  return v;
}

async function revert(admin, db, file) {
  const rb = JSON.parse(fs.readFileSync(file, "utf8"));
  const counts = {deleted: 0, restored: 0, skippedNotOurs: 0};
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops) await batch.commit();
    batch = db.batch();
    ops = 0;
  };
  for (const w of rb.writes) {
    if (w.op === "create") {
      if (w.applied !== true) {
        counts.skippedNotOurs++;
        continue;
      }
      batch.delete(db.doc(w.path));
      counts.deleted++;
    } else {
      const patch = {};
      for (const f of w.fields) {
        const b = w.before ? w.before[f] : null;
        patch[f] = b === null || b === undefined ? admin.firestore.FieldValue.delete() : fromJson(admin, b);
      }
      batch.update(db.doc(w.path), patch);
      counts.restored++;
    }
    if (++ops >= 400) await flush();
  }
  await flush();
  console.log(JSON.stringify({mode: "revert", file, counts}, null, 2));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertSafe(args);
  const compiled = path.join(__dirname, "../lib/company_chain_autolink.js");
  if (!fs.existsSync(compiled)) throw new Error("Missing functions/lib — run npm run build in functions/ first.");

  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: project,
      serviceAccountId: project === "tashil-dev" ?
        "firebase-adminsdk-fbsvc@tashil-dev.iam.gserviceaccount.com" : undefined,
    });
  }
  const db = admin.firestore();
  if (args.revert) return revert(admin, db, args.revert);
  const lib = require("../lib/company_chain_autolink");
  const dryRun = !args.apply;
  const now = args.now || new Date();
  const companies = args.company ? [args.company] : await lib.allCompanyUids(db);
  const freeChains = [...await lib.loadFreeChains(db)];
  const totals = {
    companies: companies.length, companiesWithMissingLinks: 0, chainsPerCompanyMax: 0,
    delegates: 0, eligiblePaid: 0, linksMissing: 0, created: 0,
    copiesToUpdate: 0, usersToUpdate: 0, skipped: {}, failedCompanies: 0,
  };
  const plan = [];
  if (args.rollback && !dryRun) {
    // Write the file before any write happens, then again with the results.
    fs.writeFileSync(args.rollback, JSON.stringify({project, companies, status: "starting", writes: []}));
  }
  for (const co of companies) {
    try {
      const r = await lib.reconcileCompanyChainLinks(db, co, {now, dryRun, plan});
      totals.delegates += r.delegates;
      totals.eligiblePaid += r.eligible;
      totals.linksMissing += r.pairsMissing;
      totals.created += r.created;
      totals.copiesToUpdate += r.updatedCopies;
      totals.usersToUpdate += r.updatedUsers || 0;
      totals.chainsPerCompanyMax = Math.max(totals.chainsPerCompanyMax, r.chains);
      if (r.pairsMissing) totals.companiesWithMissingLinks++;
      for (const [k, v] of Object.entries(r.skipped)) totals.skipped[k] = (totals.skipped[k] || 0) + v;
    } catch (e) {
      totals.failedCompanies++;
      console.error(`company failed: ${String(e && e.message || e).slice(0, 200)}`);
    }
  }
  if (args.rollback) {
    fs.writeFileSync(args.rollback, JSON.stringify({
      project, companies, mode: dryRun ? "dry-run" : "apply", at: new Date().toISOString(),
      writes: plan.map(toJson),
    }, null, 2));
  }
  totals.plannedCreates = plan.filter((w) => w.op === "create").length;
  totals.plannedMerges = plan.filter((w) => w.op === "merge").length;
  const report = {project, mode: dryRun ? "dry-run" : "apply", now: now.toISOString(), freeChains, totals};
  if (args.report) fs.writeFileSync(args.report, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  main().catch((e) => {
    console.error(String(e && e.message || e));
    process.exit(1);
  });
}

module.exports = {parseArgs, assertSafe};
