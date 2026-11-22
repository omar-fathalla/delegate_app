/**
 * TAS-230: give nested delegate docs without any start date a server
 * `createdAt`. With no createdAt / hiredAt / startDate /
 * subscription.startDate, DelegateModel falls back to the first document's
 * `uploadedAt` (a device clock) or to 2026-01-01, and that date decides
 * which days count as absences and whether a global force-logout applies.
 *
 * Source: the Firestore document's own `createTime` (server time, set when
 * the doc was first written). Only docs under
 * organizations/{org}/companies/{co}/delegates are read. Only `createdAt`
 * is written, and only where every date field above is missing.
 *
 * Default: dry run, prints COUNTS ONLY (no ids, no names).
 *   node scripts/backfill-delegate-created-at.js --project tashil-dev
 *   node scripts/backfill-delegate-created-at.js --project tashil-dev --apply
 * Prod needs --allow-prod-project=<id> and the user's written approval.
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget} = require("./p0-common");

const has = (v) => v !== undefined && v !== null && v !== "";

/**
 * @param {Record<string, unknown>} data delegate doc data
 * @return {"hasCreatedAt"|"hasOtherDate"|"fromUploadedAt"|"noDate"}
 */
function classifyDelegateDate(data) {
  if (has(data.createdAt)) return "hasCreatedAt";
  const sub = data.subscription && typeof data.subscription === "object" ? data.subscription : {};
  if (has(data.hiredAt) || has(data.startDate) || has(sub.startDate)) return "hasOtherDate";
  const docs = Array.isArray(data.documents) ? data.documents : [];
  if (docs.length && docs[0] && has(docs[0].uploadedAt)) return "fromUploadedAt";
  return "noDate";
}

/** Docs that get a createdAt. */
function needsCreatedAt(how) {
  return how === "fromUploadedAt" || how === "noDate";
}

async function backfill(db, apply) {
  const counts = {scanned: 0, notNested: 0, hasCreatedAt: 0, hasOtherDate: 0,
    fromUploadedAt: 0, noDate: 0, updated: 0};
  const snap = await db.collectionGroup("delegates").get();
  let batch = db.batch(); let pending = 0;
  for (const doc of snap.docs) {
    const company = doc.ref.parent.parent;
    if (!company || company.parent.id !== "companies") { counts.notNested++; continue; }
    counts.scanned++;
    const how = classifyDelegateDate(doc.data());
    counts[how]++;
    if (!apply || !needsCreatedAt(how)) continue;
    // Fails if the doc changed since it was read, so a concurrent edit that
    // added a date is never overwritten.
    batch.update(doc.ref, {createdAt: doc.createTime}, {lastUpdateTime: doc.updateTime});
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
module.exports = {backfill, classifyDelegateDate, needsCreatedAt};
