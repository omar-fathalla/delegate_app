/**
 * TAS-224: give old penalties an organizationId so org-admin and org-level
 * marketing can list them under the new rules (they list by
 * `where organizationId == org`). New penalties already carry it (TAS-73).
 *
 * Where the organization comes from, in order:
 *   1. the penalty's branch: branches/{branchId}.organizationUID
 *   2. the penalty's company, only when it sits under exactly ONE
 *      organization (organizations/{org}/companies/{companyId}).
 * A company under several chains with no usable branch is ambiguous and is
 * left alone (reported, never guessed).
 *
 * Default: dry run, prints COUNTS ONLY (no ids, no names).
 *   node scripts/backfill-penalty-organization-id.js --project tashil-dev
 *   node scripts/backfill-penalty-organization-id.js --project tashil-dev --apply
 * Prod needs --allow-prod-project=<id> and the user's written approval.
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget} = require("./p0-common");

/**
 * @param {{organizationId?: string, branchId?: string, companyId?: string}} p
 * @param {Map<string, string>} branchOrg branchId -> organizationUID
 * @param {Map<string, Set<string>>} companyOrgs companyId -> org ids
 * @return {{org: string, how: string}}
 */
function resolvePenaltyOrg(p, branchOrg, companyOrgs) {
  if (typeof p.organizationId === "string" && p.organizationId.trim()) {
    return {org: "", how: "hasOrg"};
  }
  const branchId = typeof p.branchId === "string" ? p.branchId.trim() : "";
  const fromBranch = branchId ? (branchOrg.get(branchId) || "").trim() : "";
  const companyId = typeof p.companyId === "string" ? p.companyId.trim() : "";
  const orgs = companyId ? (companyOrgs.get(companyId) || new Set()) : new Set();
  if (fromBranch) {
    // A branch of a chain the company is not linked to is suspicious: skip.
    if (orgs.size && !orgs.has(fromBranch)) return {org: "", how: "branchCompanyMismatch"};
    return {org: fromBranch, how: "byBranch"};
  }
  if (orgs.size === 1) return {org: [...orgs][0], how: "byUniqueCompany"};
  if (orgs.size > 1) return {org: "", how: "ambiguousCompany"};
  return {org: "", how: "unresolved"};
}

async function loadMaps(db) {
  const branchOrg = new Map();
  (await db.collection("branches").get()).docs.forEach((d) => {
    const org = d.get("organizationUID");
    if (typeof org === "string" && org.trim()) branchOrg.set(d.id, org.trim());
  });
  const companyOrgs = new Map();
  (await db.collectionGroup("companies").get()).docs.forEach((d) => {
    const parent = d.ref.parent.parent;
    if (!parent || parent.parent.id !== "organizations") return;
    if (!companyOrgs.has(d.id)) companyOrgs.set(d.id, new Set());
    companyOrgs.get(d.id).add(parent.id);
  });
  return {branchOrg, companyOrgs};
}

async function backfill(db, apply) {
  const {branchOrg, companyOrgs} = await loadMaps(db);
  const counts = {scanned: 0, hasOrg: 0, byBranch: 0, byUniqueCompany: 0,
    branchCompanyMismatch: 0, ambiguousCompany: 0, unresolved: 0, updated: 0};
  const snap = await db.collection("penalties").get();
  let batch = db.batch(); let pending = 0;
  for (const doc of snap.docs) {
    counts.scanned++;
    const {org, how} = resolvePenaltyOrg(doc.data(), branchOrg, companyOrgs);
    counts[how]++;
    if (!org || !apply) continue;
    // Only fills the missing field; nothing else on the penalty changes.
    batch.update(doc.ref, {organizationId: org});
    pending++; counts.updated++;
    if (pending === 400) { await batch.commit(); batch = db.batch(); pending = 0; }
  }
  if (apply && pending) await batch.commit();
  return counts;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  admin.initializeApp({projectId: project});
  const c = await backfill(admin.firestore(), args.apply);
  console.log(JSON.stringify({mode: args.apply ? "apply" : "dry-run", project, ...c}));
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = {backfill, resolvePenaltyOrg};
