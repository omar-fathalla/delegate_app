/**
 * Backfill staff JWT `phones` custom claims from users/{uid}.phoneNumber.
 *
 * Dry-run by default. See README-staff-phones-claim-backfill.md.
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget, newBackfillRunId} = require("./p0-common");
const {
  shouldProcessStaffUser,
  staffPhonesFromStoredPhone,
  mergeStaffPhonesClaims,
  decideStaffPhonesMint,
} = require("../lib/staff_phones_claim_logic");
const {hasStaffPhoneCollision, readAuthCustomClaims} = require("../lib/staff_phones_claim_query");

function str(v) {
  return typeof v === "string" ? v.trim() : "";
}

async function scanStaffUsers(db) {
  const out = [];
  let last = null;
  for (;;) {
    let q = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(300);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const data = doc.data();
      if (!shouldProcessStaffUser(data)) continue;
      out.push({uid: doc.id, data});
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 300) break;
  }
  return out;
}

async function planOne(db, uid, data) {
  const phone = data.phoneNumber;
  const phones = staffPhonesFromStoredPhone(phone);
  const collision = phones.length > 0
    ? await hasStaffPhoneCollision(db, uid, str(phone))
    : false;
  const decision = decideStaffPhonesMint(phone, collision, false);
  const existing = await readAuthCustomClaims(uid);
  const next = mergeStaffPhonesClaims(existing, decision);
  const prevPhones = existing.phones;
  const changed = JSON.stringify(prevPhones ?? null) !== JSON.stringify(next.phones ?? null);
  return {uid, decision, changed, variantCount: phones.length};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  const apply = args.apply;
  const runId = newBackfillRunId("staff-phones-claim");

  if (!admin.apps.length) {
    admin.initializeApp({projectId: project});
  }
  const db = admin.firestore();

  console.log(JSON.stringify({runId, project, apply, dryRun: !apply}));

  const staff = await scanStaffUsers(db);
  let wouldSet = 0;
  let wouldClear = 0;
  let skippedCollision = 0;
  let unchanged = 0;
  let applied = 0;

  for (const row of staff) {
    const plan = await planOne(db, row.uid, row.data);
    if (plan.decision.action === "skip") {
      skippedCollision += 1;
      console.log(JSON.stringify({uid: row.uid, action: "skip", reason: plan.decision.reason}));
      continue;
    }
    if (!plan.changed) {
      unchanged += 1;
      continue;
    }
    if (plan.decision.action === "set") wouldSet += 1;
    if (plan.decision.action === "clear") wouldClear += 1;

    if (apply) {
      const existing = await readAuthCustomClaims(row.uid);
      const next = mergeStaffPhonesClaims(existing, plan.decision);
      await admin.auth().setCustomUserClaims(row.uid, next);
      applied += 1;
    }
  }

  console.log(JSON.stringify({
    runId,
    staffScanned: staff.length,
    wouldSet,
    wouldClear,
    skippedCollision,
    unchanged,
    applied: apply ? applied : 0,
    mode: apply ? "apply" : "dry-run",
  }));
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});