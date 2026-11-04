/**
 * P0: remove plaintext password fields from users/*.
 *
 * Default: dry run, prints COUNTS ONLY (no paths, no values).
 *   node scripts/purge-password-fields.js --project tashil-dev
 *   node scripts/purge-password-fields.js --project tashil-dev --apply
 * Allow-list: tashil-dev and demo-* only; prod needs --allow-prod-project=<id>
 * and written approval (not given).
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget, secretKeysPresent, SECRET_KEYS} = require("./p0-common");

async function purge(db, apply) {
  const counts = {scanned: 0, withSecret: 0, updated: 0};
  for (const k of SECRET_KEYS) counts[k] = 0;
  const snap = await db.collection("users").get();
  let batch = db.batch(); let pending = 0;
  for (const doc of snap.docs) {
    counts.scanned++;
    const keys = secretKeysPresent(doc.data());
    if (!keys.length) continue;
    counts.withSecret++;
    for (const k of keys) counts[k]++;
    if (!apply) continue;
    const del = {};
    for (const k of keys) del[k] = admin.firestore.FieldValue.delete();
    batch.update(doc.ref, del); pending++; counts.updated++;
    if (pending === 400) { await batch.commit(); batch = db.batch(); pending = 0; }
  }
  if (apply && pending) await batch.commit();
  return counts;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  admin.initializeApp({projectId: project});
  const c = await purge(admin.firestore(), args.apply);
  console.log(JSON.stringify({mode: args.apply ? "apply" : "dry-run", project, ...c}));
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = {purge};
