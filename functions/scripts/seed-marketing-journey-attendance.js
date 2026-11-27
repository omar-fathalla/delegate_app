#!/usr/bin/env node
/**
 * TAS-393: today's fake check-ins on «Fake Branch Alpha» (seed-fake-hr-org)
 * for the marketing Maestro / Patrol journeys on tashil-dev ONLY.
 *
 * Writes 3 attendance_logs docs with fixed ids per day
 * (`seed-fake-journey-<yyyymmdd>-<delegate>`, seedTag `journey-tas393`), so a
 * rerun the same day overwrites instead of adding. Fake delegates only.
 *
 *   node scripts/seed-marketing-journey-attendance.js --project tashil-dev
 *   node scripts/seed-marketing-journey-attendance.js --project tashil-dev --apply
 */
"use strict";

const PROJECT = "tashil-dev";
const ORG = "seed-fake-hr-org";
const BRANCH_ID = "seed-fake-br-alpha";
const BRANCH_NAME = "Fake Branch Alpha";
const DELEGATES = [
  ["seed-fake-del-alpha-1", "seed-fake-co-alpha", 8, 5],
  ["seed-fake-del-alpha-2", "seed-fake-co-alpha", 8, 40],
  ["seed-fake-del-beta-1", "seed-fake-co-beta", 9, 10],
];

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  const project = argValue("--project");
  if (project !== PROJECT) {
    throw new Error(`refusing: --project must be ${PROJECT}`);
  }
  const apply = process.argv.includes("--apply");
  const now = new Date();
  const day = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}`;
  if (!apply) {
    console.log(`dry run: would write ${DELEGATES.length} check-ins for ${day} on ${BRANCH_NAME}`);
    return;
  }
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT });
  const db = admin.firestore();
  const branch = await db.doc(`organizations/${ORG}/branches/${BRANCH_ID}`).get();
  if (!branch.exists) throw new Error(`missing ${BRANCH_ID}; run hr-web-fake-accounts.js --apply first`);
  for (const [delegateId, companyId, h, m] of DELEGATES) {
    const del = await db.doc(`organizations/${ORG}/companies/${companyId}/delegates/${delegateId}`).get();
    if (!del.exists) throw new Error(`missing fake delegate ${delegateId}`);
    const at = new Date(now);
    at.setHours(h, m, 0, 0);
    const id = `seed-fake-journey-${day}-${delegateId}`;
    await db.collection("attendance_logs").doc(id).set({
      type: "check_in",
      delegateId,
      userId: delegateId,
      delegateName: del.data().fullName,
      organizationId: ORG,
      organizationUID: ORG,
      companyId,
      companyUID: companyId,
      branchName: BRANCH_NAME,
      branchId: BRANCH_ID,
      phoneNumber: del.data().phoneNumber,
      timestamp: admin.firestore.Timestamp.fromDate(at),
      latitude: branch.data().latitude ?? 0,
      longitude: branch.data().longitude ?? 0,
      seedTag: "journey-tas393",
    });
    console.log(`wrote ${id}`);
  }
}

main().catch((e) => {
  console.error(`seed-marketing-journey-attendance: ${e.message}`);
  process.exit(1);
});
