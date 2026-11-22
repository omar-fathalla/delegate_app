/**
 * TAS-251: delete "ghost" delegate link docs: device-only docs that old app
 * builds re-created after a delegate was deleted (docs/security/GHOST_DELEGATE_DOCS.md).
 *
 * A doc is a ghost when, under organizations/{org}/companies/{co}/delegates:
 *   - it has no name, national ID or phone (same field lists as
 *     functions/src/delegate_identity.ts, checked by a test), and
 *   - it has no status, no approvedRequestId and no subscription.
 * Nothing else is touched: no users docs, no Auth users, no other paths.
 *
 * Default: dry run, prints COUNTS ONLY. --apply needs --backup=<file.json>
 * (written BEFORE any delete, outside the repo; holds path + data of every
 * doc that will be deleted). Each delete is guarded by the doc's
 * updateTime, so a doc changed since it was read is left alone.
 *   node scripts/cleanup-ghost-delegate-docs.js --project tashil-dev
 *   node scripts/cleanup-ghost-delegate-docs.js --project tashil-dev --apply --backup=/tmp/ghosts.json
 * Prod needs --allow-prod-project=<id> and the user's written approval.
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const {parseArgs, assertTarget} = require("./p0-common");

// Keep in sync with functions/src/delegate_identity.ts (a test compares them).
const NAME_FIELDS = ["fullName", "firstName", "middleName", "lastName", "name"];
const NATIONAL_ID_FIELDS = ["nationalityID", "nationalityId", "nationalId", "nationalID", "national_id", "idNumber"];
const PHONE_FIELDS = ["phoneNumber", "phone", "mobile", "mobileNumber"];

function filled(v) {
  if (typeof v === "string") return v.trim().length > 0;
  if (typeof v === "number") return Number.isFinite(v);
  return false;
}

/** @param {Record<string, unknown>} data */
function hasIdentity(data) {
  return [...NAME_FIELDS, ...NATIONAL_ID_FIELDS, ...PHONE_FIELDS].some((f) => filled(data[f]));
}

/**
 * @param {Record<string, unknown>} data delegate doc data
 * @return {"real"|"hasState"|"ghost"}
 */
function classifyDelegateDoc(data) {
  if (hasIdentity(data)) return "real";
  const sub = data.subscription;
  if (filled(data.status) || filled(data.approvedRequestId) ||
      (sub && typeof sub === "object" && Object.keys(sub).length)) return "hasState";
  return "ghost";
}

function toJson(v) {
  if (v instanceof admin.firestore.Timestamp) return {_ts: v.toDate().toISOString()};
  if (Array.isArray(v)) return v.map(toJson);
  if (v && typeof v === "object") {
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toJson(x)]));
  }
  return v;
}

async function findGhosts(db) {
  const counts = {scanned: 0, notNested: 0, real: 0, hasState: 0, ghost: 0};
  const ghosts = [];
  const snap = await db.collectionGroup("delegates").get();
  for (const doc of snap.docs) {
    const company = doc.ref.parent.parent;
    if (!company || company.parent.id !== "companies") { counts.notNested++; continue; }
    counts.scanned++;
    const how = classifyDelegateDoc(doc.data());
    counts[how]++;
    if (how === "ghost") ghosts.push(doc);
  }
  return {counts, ghosts};
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {{apply: boolean, backup?: string, project?: string}} opts
 */
async function cleanup(db, opts) {
  const {counts, ghosts} = await findGhosts(db);
  counts.deleted = 0;
  if (!opts.apply) return counts;
  if (!opts.backup) throw new Error("--apply needs --backup=<file.json>.");
  const backupPath = path.resolve(opts.backup);
  fs.writeFileSync(backupPath, JSON.stringify({
    project: opts.project || "", takenAt: new Date().toISOString(),
    docs: ghosts.map((d) => ({path: d.ref.path, createTime: d.createTime.toDate().toISOString(), data: toJson(d.data())})),
  }, null, 2), {mode: 0o600});
  let batch = db.batch(); let pending = 0;
  for (const doc of ghosts) {
    batch.delete(doc.ref, {lastUpdateTime: doc.updateTime});
    pending++; counts.deleted++;
    if (pending === 400) { await batch.commit(); batch = db.batch(); pending = 0; }
  }
  if (pending) await batch.commit();
  counts.backup = backupPath;
  return counts;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  const backupArg = args.rest.find((a) => a.startsWith("--backup="));
  admin.initializeApp({projectId: project});
  const c = await cleanup(admin.firestore(), {
    apply: args.apply, backup: backupArg ? backupArg.slice(9) : undefined, project,
  });
  console.log(JSON.stringify({mode: args.apply ? "apply" : "dry-run", project, ...c}));
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = {cleanup, classifyDelegateDoc, hasIdentity, NAME_FIELDS, NATIONAL_ID_FIELDS, PHONE_FIELDS};
