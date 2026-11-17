/**
 * Backfill staff JWT `phones` custom claims from users/{uid}.phoneNumber
 * (or the Auth phoneNumber when one is set).
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
  resolveStaffMintPhone,
} = require("../lib/staff_phones_claim_logic");
const {buildPhoneOwnerIndex, indexedStaffPhoneCollision} = require("../lib/staff_phones_claim_query");

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

/** Collision is checked against every phone field in users and delegates, normalized. */
async function runStaffPhonesBackfill(db, auth, {apply, log = () => undefined}) {
  const ownerIndex = await buildPhoneOwnerIndex(db);
  const staff = await scanStaffUsers(db);
  const counts = {
    staffScanned: staff.length, wouldSet: 0, wouldClear: 0,
    skippedCollision: 0, missingAuthUser: 0, unchanged: 0, applied: 0,
  };

  for (const row of staff) {
    let authUser;
    try {
      authUser = await auth.getUser(row.uid);
    } catch (e) {
      counts.missingAuthUser += 1;
      log({uid: row.uid, action: "none", reason: "no_auth_user"});
      continue;
    }
    const mint = resolveStaffMintPhone(authUser.phoneNumber, row.data.phoneNumber);
    const collision = staffPhonesFromStoredPhone(mint.phone).length > 0 &&
      indexedStaffPhoneCollision(ownerIndex, row.uid, mint.phone);
    const decision = decideStaffPhonesMint(mint.phone, collision);
    const existing = {...(authUser.customClaims || {})};
    const next = mergeStaffPhonesClaims(existing, decision);
    const changed = JSON.stringify(existing.phones ?? null) !== JSON.stringify(next.phones ?? null);

    if (decision.reason === "phone_collision") {
      counts.skippedCollision += 1;
      log({uid: row.uid, action: "skip", reason: decision.reason, clearsExisting: changed});
    }
    if (!changed) {
      counts.unchanged += 1;
      continue;
    }
    if (decision.action === "set") counts.wouldSet += 1;
    if (decision.action === "clear") counts.wouldClear += 1;

    if (apply) {
      await auth.setCustomUserClaims(row.uid, next);
      counts.applied += 1;
    }
  }
  return counts;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  const apply = args.apply;
  const runId = newBackfillRunId("staff-phones-claim");

  if (!admin.apps.length) {
    admin.initializeApp({projectId: project});
  }

  console.log(JSON.stringify({runId, project, apply, dryRun: !apply}));
  const counts = await runStaffPhonesBackfill(admin.firestore(), admin.auth(), {
    apply,
    log: (row) => console.log(JSON.stringify(row)),
  });
  console.log(JSON.stringify({runId, ...counts, applied: apply ? counts.applied : 0, mode: apply ? "apply" : "dry-run"}));
}

module.exports = {runStaffPhonesBackfill};

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}
