#!/usr/bin/env node
/**
 * TAS-23: give every staff account the custom claims the claim-reading
 * callables trust: {role, orgId, organizationId, companyId}. Covers every
 * staff role (super-admin, technical_support, accountant, organization-admin,
 * company-admin / admin, supervisor, hr, marketing, marketing_promotion,
 * branches_marketing, and their old spellings). Logic shared with the sync
 * trigger: src/staff_claims_sync_logic.ts (planBackfill).
 *
 *   npm run build      # loads lib/staff_claims_sync_logic
 *   node scripts/backfill_staff_claims.js --project tashil-dev                 # dry-run (default)
 *   node scripts/backfill_staff_claims.js --project tashil-dev --apply         # write claims
 *   node scripts/backfill_staff_claims.js --project tashil-dev --apply --allow-file verified-uids.json
 *   node scripts/backfill_staff_claims.js --project tashil-dev --rollback <backup.json>
 *
 * --project is required. tashil-dev and demo-* (emulator) run as given. The
 * production project also needs --allow-prod-project=practice-firebase-72df1
 * (dry-run included), and --apply on production only with the user's go.
 *
 * Who gets claims (planBackfill):
 *   ok      claims already match the users doc (role, org, company).
 *   set     the users doc role/scope is confirmed by a server membership
 *           (organizations/{org}/members/{uid} or .../companies/{co}/members/{uid}),
 *           or the account already holds the same role claim in the same scope,
 *           or the uid is in --allow-file (a JSON array of uids checked by hand).
 *   manual  nothing server-side confirms it (users doc alone is not proof),
 *           global roles (super-admin / technical_support / accountant) not in
 *           --allow-file, missing org/company, or an account with delegate claims.
 *   skip    not staff, no Auth user, or Auth user disabled.
 * Existing claims are kept and merged; only the four staff keys are written.
 *
 * Output: counts by role, and rows with masked uids only (no emails, phones,
 * names). Files go to --out (default ~/tashil-claims-backfill):
 *   report-<project>-<stamp>.json   every row (uid, role, action, reason)
 *   backup-claims-<project>-<stamp>.json   claims before --apply, for --rollback
 * --rollback restores the "before" claims of each uid in the backup, but only
 * where the claims still equal what the apply wrote (else it reports a
 * conflict; --force restores anyway).
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const PROD = "practice-firebase-72df1";

function parseArgs(argv) {
  const get = (name) => {
    const eq = argv.find((a) => a.startsWith(`${name}=`));
    if (eq) return eq.slice(name.length + 1);
    const i = argv.indexOf(name);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  return {
    project: get("--project"),
    apply: argv.includes("--apply"),
    rollback: get("--rollback"),
    allowFile: get("--allow-file"),
    allowProd: get("--allow-prod-project"),
    force: argv.includes("--force"),
    out: get("--out") || path.join(os.homedir(), "tashil-claims-backfill"),
    quiet: argv.includes("--quiet"),
  };
}

const mask = (uid) => (uid.length <= 8 ? `${uid.slice(0, 2)}…` : `${uid.slice(0, 6)}…${uid.slice(-2)}`);

function checkProject(o) {
  if (!o.project) throw new Error("usage: --project <id> [--apply] [--allow-file f] [--rollback f]");
  if (o.project === PROD && o.allowProd !== PROD) {
    throw new Error(`production needs --allow-prod-project=${PROD} (and the user's go for --apply)`);
  }
  if (o.project !== PROD && o.project !== "tashil-dev" && !o.project.startsWith("demo-")) {
    throw new Error(`unknown project ${o.project}: only tashil-dev, demo-* or ${PROD}`);
  }
}

async function rollback(admin, o, log) {
  const rows = JSON.parse(fs.readFileSync(o.rollback, "utf8"));
  if (rows.project && rows.project !== o.project) throw new Error(`backup is for ${rows.project}, not ${o.project}`);
  let restored = 0; let conflicts = 0;
  for (const r of rows.rows || rows) {
    const u = await admin.auth().getUser(r.uid).catch(() => null);
    if (!u) { log(`  missing ${mask(r.uid)}`); continue; }
    const now = u.customClaims || {};
    if (r.after && JSON.stringify(now) !== JSON.stringify(r.after) && !o.force) {
      conflicts++;
      log(`  conflict ${mask(r.uid)}: claims changed since the apply (use --force to restore anyway)`);
      continue;
    }
    await admin.auth().setCustomUserClaims(r.uid, r.before && Object.keys(r.before).length ? r.before : null);
    restored++;
  }
  log(`rolled back ${restored} accounts, conflicts ${conflicts}, from ${path.basename(o.rollback)}`);
  return {restored, conflicts};
}

async function run(argv, deps = {}) {
  const o = parseArgs(argv);
  checkProject(o);
  const log = deps.log || ((m) => { if (!o.quiet) console.log(m); });
  const admin = deps.admin || require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: o.project});
  const L = require("../lib/staff_claims_sync_logic");
  const db = admin.firestore();
  fs.mkdirSync(o.out, {recursive: true, mode: 0o700});
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");

  if (o.rollback) return rollback(admin, o, log);
  log(`project: ${o.project}   mode: ${o.apply ? "APPLY (writes claims)" : "DRY-RUN (read only)"}`);

  const allow = new Set(o.allowFile ? JSON.parse(fs.readFileSync(o.allowFile, "utf8")) : []);

  const snap = await db.collection("users")
    .select("role", "organizationUID", "organizationId", "companyUID", "companyId").get();
  const staff = snap.docs.filter((d) => L.canonicalStaffRole(d.get("role")));

  const authUsers = new Map();
  for (let i = 0; i < staff.length; i += 100) {
    const res = await admin.auth().getUsers(staff.slice(i, i + 100).map((d) => ({uid: d.id})));
    res.users.forEach((u) => authUsers.set(u.uid, u));
  }

  const rows = [];
  for (const d of staff) {
    const doc = d.data();
    const u = authUsers.get(d.id);
    const want = L.desiredFromDoc(doc).claims;
    const paths = want ? L.membershipPaths(d.id, want) : [];
    const members = [];
    for (const p of paths) {
      const m = await db.doc(p).get();
      members.push(m.exists ? m.data() : null);
    }
    const plan = L.planBackfill({
      doc, claims: u && u.customClaims, authExists: !!u, authDisabled: !!(u && u.disabled),
      members, allowListed: allow.has(d.id),
    });
    rows.push({uid: d.id, role: L.canonicalStaffRole(doc.role), rawRole: doc.role, ...plan,
      claimsBefore: (u && u.customClaims) || {}});
  }

  // Counts by role and action.
  const byRole = {};
  for (const r of rows) {
    byRole[r.role] = byRole[r.role] || {ok: 0, set: 0, manual: 0, skip: 0};
    byRole[r.role][r.action]++;
  }
  const total = {ok: 0, set: 0, manual: 0, skip: 0};
  rows.forEach((r) => total[r.action]++);
  log(`\nstaff users docs: ${rows.length}   ok ${total.ok}   set ${total.set}   manual ${total.manual}   skip ${total.skip}`);
  log("role                 ok   set  manual  skip");
  for (const [role, c] of Object.entries(byRole).sort()) {
    log(`  ${role.padEnd(18)} ${String(c.ok).padStart(4)} ${String(c.set).padStart(5)} ${String(c.manual).padStart(7)} ${String(c.skip).padStart(5)}`);
  }
  const reasons = {};
  rows.filter((r) => r.action !== "ok").forEach((r) => {
    const k = `${r.action} | ${r.role} | ${r.reason}`;
    reasons[k] = (reasons[k] || 0) + 1;
  });
  log("\nby reason:");
  Object.entries(reasons).sort().forEach(([k, n]) => log(`  ${String(n).padStart(4)}  ${k}`));
  log("\nmanual rows (masked uid):");
  rows.filter((r) => r.action === "manual").forEach((r) => log(`  ${mask(r.uid).padEnd(12)} ${r.role.padEnd(18)} ${r.reason}`));

  const reportFile = path.join(o.out, `report-${o.project}-${stamp}.json`);
  fs.writeFileSync(reportFile, JSON.stringify(rows.map(({claimsBefore, ...r}) => ({
    ...r, hadStaffClaim: !!L.currentStaffClaims(claimsBefore),
  })), null, 1), {mode: 0o600});
  log(`\nreport: ${reportFile}`);

  if (!o.apply) {
    log("DRY-RUN: nothing was changed. Re-run with --apply to write the 'set' rows.");
    return {rows, total, byRole, reportFile};
  }

  const toSet = rows.filter((r) => r.action === "set");
  const backup = {project: o.project, createdAt: new Date().toISOString(), rows: []};
  let done = 0;
  for (const r of toSet) {
    // Fresh read right before the write, so nothing set meanwhile is lost.
    const before = (await admin.auth().getUser(r.uid)).customClaims || {};
    const after = L.mergeStaffClaims(before, r.want);
    backup.rows.push({uid: r.uid, before, after});
    await admin.auth().setCustomUserClaims(r.uid, after);
    done++;
  }
  const backupFile = path.join(o.out, `backup-claims-${o.project}-${stamp}.json`);
  fs.writeFileSync(backupFile, JSON.stringify(backup, null, 1), {mode: 0o600});

  let verified = 0;
  for (const r of toSet) {
    const c = (await admin.auth().getUser(r.uid)).customClaims || {};
    if (L.claimsWritten(c, r.want)) verified++;
  }
  log(`\nAPPLIED: ${done} accounts, read back OK: ${verified}/${toSet.length}`);
  log(`backup of previous claims: ${backupFile}`);
  log(`rollback: node scripts/backfill_staff_claims.js --project ${o.project}` +
    `${o.project === PROD ? ` --allow-prod-project=${PROD}` : ""} --rollback ${backupFile}`);
  log("New claims reach each user's ID token on its next refresh (<= 1 hour) or next sign-in.");
  return {rows, total, byRole, reportFile, backupFile, done, verified};
}

if (require.main === module) {
  run(process.argv.slice(2)).catch((e) => { console.error("ERROR", e.message); process.exit(1); });
}

module.exports = {run, parseArgs, mask};
