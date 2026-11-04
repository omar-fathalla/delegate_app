/**
 * P0: canonical role list with per-role COUNTS ONLY (read-only).
 *   node scripts/role-counts.js --project tashil-dev
 * Reads only the `role` field. Allow-list: tashil-dev and demo-* only; prod needs
 * --allow-prod-project=<id> and written approval (not given).
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget} = require("./p0-common");

async function counts(db) {
  const snap = await db.collection("users").select("role").get();
  const out = {};
  for (const d of snap.docs) {
    const r = d.get("role");
    const k = typeof r === "string" ? r : "(none)";
    out[k] = (out[k] || 0) + 1;
  }
  return {total: snap.size, byRole: out};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.apply) throw new Error("role-counts is read-only; --apply is not supported.");
  const project = assertTarget(args);
  admin.initializeApp({projectId: project});
  console.log(JSON.stringify({project, ...(await counts(admin.firestore()))}));
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = {counts};
