/**
 * TAS-225: give old delegate users docs a companyUID. Under the new rules HR
 * and supervisors read or update a users doc only when its companyUID is
 * their own company, so a users doc without one is invisible to them (the
 * leave-balance copy, profile lookups).
 *
 * Source: the delegate's company doc with the same id,
 * organizations/{org}/companies/{companyId}/delegates/{uid}.
 *   - one company  -> companyUID is set; organizationUID too when it is
 *                     missing and the delegate sits under one org only.
 *   - several companies, or none -> left alone and counted.
 * Only users with role delegate / promoter are touched, and only missing
 * fields are written.
 *
 * Default: dry run, prints COUNTS ONLY (no ids, no names).
 *   node scripts/backfill-delegate-users-company.js --project tashil-dev
 *   node scripts/backfill-delegate-users-company.js --project tashil-dev --apply
 * Prod needs --allow-prod-project=<id> and the user's written approval.
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget} = require("./p0-common");

const FIELD_ROLES = new Set(["delegate", "promoter"]);

/**
 * @param {Record<string, unknown>} user users doc data
 * @param {{companies: Set<string>, orgs: Set<string>} | undefined} placement
 * @return {{how: string, patch: Record<string, string>}}
 */
function resolveUserCompany(user, placement) {
  const role = typeof user.role === "string" ? user.role.trim().toLowerCase() : "";
  if (!FIELD_ROLES.has(role)) return {how: "notDelegate", patch: {}};
  const has = (k) => typeof user[k] === "string" && user[k].trim() !== "";
  if (has("companyUID")) return {how: "hasCompany", patch: {}};
  if (!placement || placement.companies.size === 0) return {how: "noDelegateDoc", patch: {}};
  if (placement.companies.size > 1) return {how: "severalCompanies", patch: {}};
  const patch = {companyUID: [...placement.companies][0]};
  if (!has("organizationUID") && placement.orgs.size === 1) {
    patch.organizationUID = [...placement.orgs][0];
  }
  return {how: "filled", patch};
}

async function loadPlacements(db) {
  const map = new Map();
  (await db.collectionGroup("delegates").select().get()).docs.forEach((d) => {
    const company = d.ref.parent.parent;
    const org = company && company.parent.parent;
    if (!company || !org || company.parent.id !== "companies" || org.parent.id !== "organizations") return;
    if (!map.has(d.id)) map.set(d.id, {companies: new Set(), orgs: new Set()});
    map.get(d.id).companies.add(company.id);
    map.get(d.id).orgs.add(org.id);
  });
  return map;
}

async function backfill(db, apply) {
  const placements = await loadPlacements(db);
  const counts = {scanned: 0, notDelegate: 0, hasCompany: 0, filled: 0, withOrg: 0,
    severalCompanies: 0, noDelegateDoc: 0, updated: 0};
  const snap = await db.collection("users").where("role", "in", ["delegate", "promoter"]).get();
  let batch = db.batch(); let pending = 0;
  for (const doc of snap.docs) {
    counts.scanned++;
    const {how, patch} = resolveUserCompany(doc.data(), placements.get(doc.id));
    counts[how]++;
    if (patch.organizationUID) counts.withOrg++;
    if (how !== "filled" || !apply) continue;
    batch.update(doc.ref, patch);
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
module.exports = {backfill, resolveUserCompany};
