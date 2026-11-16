#!/usr/bin/env node
/**
 * Backfill invite_email_index from pending invites. Dry-run by default.
 *
 *   node functions/scripts/backfill-invite-email-index.js --project tashil-dev
 *   node functions/scripts/backfill-invite-email-index.js --project tashil-dev --apply
 *
 * Prod requires Mohamed's go and --allow-prod-project=practice-firebase-72df1 --apply
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget} = require("./p0-common");
const {
  INVITE_EMAIL_INDEX_COLLECTION,
  inviteEmailIndexDocId,
  inviteEmailIndexFromInvite,
} = require("../lib/invite_email_index_logic");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  const apply = args.apply === true;
  if (!admin.apps.length) admin.initializeApp({projectId: project});
  const db = admin.firestore();

  const snap = await db.collection("invites").where("status", "==", "pending").get();
  let wouldWrite = 0;
  let skipped = 0;
  const batchSize = 400;
  let batch = db.batch();
  let ops = 0;

  for (const doc of snap.docs) {
    const body = inviteEmailIndexFromInvite(doc.id, doc.data());
    if (!body) {
      skipped++;
      continue;
    }
    const email = inviteEmailIndexDocId(doc.data().email);
    if (!email) {
      skipped++;
      continue;
    }
    wouldWrite++;
    if (apply) {
      batch.set(db.collection(INVITE_EMAIL_INDEX_COLLECTION).doc(email), {
        ...body,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      ops++;
      if (ops >= batchSize) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
  }
  if (apply && ops > 0) await batch.commit();

  console.log(
    JSON.stringify(
      {
        project,
        mode: apply ? "apply" : "dry-run",
        pendingInvites: snap.size,
        wouldWrite,
        skipped,
        written: apply ? wouldWrite : 0,
      },
      null,
      2,
    ),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});