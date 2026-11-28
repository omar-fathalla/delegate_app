#!/usr/bin/env node
/**
 * TAS-379: a November month like the reported case (Dunia) for the M31
 * delegate dlg_dev_test_1 on tashil-dev ONLY: 21 days with a check-in,
 * three branches a day (three sessions), and one session from 10 Nov to
 * 12 Nov. The home card and the attendance tab must then both show
 * 21 present / 3 absent on 28 Nov.
 *
 * Fixed ids (`seed-fake-tas379-<day>-<n>`) and seedTag `tas379`: a rerun
 * rewrites the same sessions. Closed sessions only (checkOutTime set).
 *
 *   node scripts/seed-tas379-month-sessions.js --project tashil-dev [--apply]
 */
"use strict";

const PROJECT = "tashil-dev";
const ORG = "org_dev_test";
const CO = "co_dev_test";
const DEL = "dlg_dev_test_1";
const BRANCH = "br_dev_test";
const DAYS = [1, 2, 3, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 26, 27, 28];

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  if (argValue("--project") !== PROJECT) throw new Error(`refusing: --project must be ${PROJECT}`);
  const plan = [];
  for (const d of DAYS) {
    if (d === 10) {
      plan.push([`seed-fake-tas379-10-1`, new Date(2026, 10, 10, 10, 40), new Date(2026, 10, 12, 9, 0)]);
      continue;
    }
    plan.push([`seed-fake-tas379-${d}-1`, new Date(2026, 10, d, 9), new Date(2026, 10, d, 11)]);
    plan.push([`seed-fake-tas379-${d}-2`, new Date(2026, 10, d, 12), new Date(2026, 10, d, 14)]);
    plan.push([`seed-fake-tas379-${d}-3`, new Date(2026, 10, d, 15), new Date(2026, 10, d, 18)]);
  }
  if (!process.argv.includes("--apply")) {
    console.log(`dry run: would write ${plan.length} closed sessions for ${DEL} in November 2026`);
    return;
  }
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: PROJECT });
  const db = admin.firestore();
  const T = admin.firestore.Timestamp;
  const branch = (await db.doc(`organizations/${ORG}/branches/${BRANCH}`).get()).data() || {};
  const batch = db.batch();
  for (const [id, inAt, outAt] of plan) {
    batch.set(db.collection("attendance_logs").doc(id), {
      type: "check_in",
      delegateId: DEL,
      userId: DEL,
      delegateName: "مندوب تجريبي",
      organizationId: ORG,
      organizationUID: ORG,
      companyId: CO,
      companyUID: CO,
      branchId: BRANCH,
      branchName: branch.name || "فرع تجريبي DEV",
      timestamp: T.fromDate(inAt),
      checkOutTime: T.fromDate(outAt),
      location: { latitude: branch.latitude ?? 0, longitude: branch.longitude ?? 0 },
      seedTag: "tas379",
      isTestData: true,
      fake: true,
    });
  }
  await batch.commit();
  console.log(`wrote ${plan.length} sessions (${DAYS.length} days)`);
}

main().catch((e) => {
  console.error(`seed-tas379-month-sessions: ${e.message}`);
  process.exit(1);
});
