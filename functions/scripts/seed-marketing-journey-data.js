#!/usr/bin/env node
/**
 * TAS-393: fixed fake data for the marketing Maestro / Patrol journeys on
 * tashil-dev ONLY (chain seed-fake-hr-org, account seed-fake-marketing-alpha).
 *
 * Every write has a fixed id and seedTag `journey-tas393`, so a rerun
 * overwrites (resets) instead of adding:
 * - today's 3 check-ins on «Fake Branch Alpha»
 *   (`attendance_logs/seed-fake-journey-<yyyymmdd>-<delegate>`);
 * - 2 tasks assigned to the marketing user, back to pending / inProgress;
 * - 2 field photos on permission seed-fake-tas392-pp1;
 * - 1 issued penalty on Fake Company Alpha;
 * - 2 notifications for the marketing user (one unread).
 *
 *   node scripts/seed-marketing-journey-data.js --project tashil-dev
 *   node scripts/seed-marketing-journey-data.js --project tashil-dev --apply
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

  const T = admin.firestore.Timestamp;
  const dayAt = (n, h) => {
    const d = new Date(now.getTime() + n * 86400000);
    d.setHours(h, 0, 0, 0);
    return T.fromDate(d);
  };
  const MKT = "seed-fake-marketing-alpha";
  const CO = "seed-fake-co-alpha";
  const tag = { seedTag: "journey-tas393", isTestData: true, fake: true };

  // Tasks: reset to pending / inProgress (the journey starts and finishes them).
  const tasks = [
    ["seed-fake-tas393-task-1", "مراجعة رف العروض في Fake Branch Alpha",
      "اتأكد إن أسعار العروض ظاهرة وصوّر الرف.", "pending", 2],
    ["seed-fake-tas393-task-2", "متابعة حضور مناديب Fake Company Alpha",
      "اعمل مرور على المناديب الحاضرين النهارده.", "inProgress", 1],
  ];
  for (const [id, title, description, status, due] of tasks) {
    await db.doc(`organizations/${ORG}/tasks/${id}`).set({
      uid: id, title, description, priority: "medium", status,
      assignedTo: MKT, assignedToName: "Fake Branch Marketing alpha",
      companyId: CO, createdBy: "seed-fake-supervisor-alpha",
      createdByName: "Fake Supervisor alpha",
      dueDate: dayAt(due, 17), createdAt: dayAt(-1, 10), ...tag,
    });
    console.log(`task ${id} ${status}`);
  }

  // Field photos on the approved permission (image reused from the dev photo).
  const pp = `organizations/${ORG}/companies/${CO}/photo_permissions/seed-fake-tas392-pp1`;
  if ((await db.doc(pp).get()).exists) {
    const tmpl = (await db.collection(
      "organizations/org_dev_test/companies/co_dev_test/photo_permissions/perm_dev_test_m31_20261110/captured_photos",
    ).limit(1).get()).docs[0]?.data();
    for (const [id, dUid, dName, h] of [
      ["seed-fake-tas393-photo-1", "seed-fake-del-alpha-1", "Fake Delegate alpha 1", 9],
      ["seed-fake-tas393-photo-2", "seed-fake-del-alpha-2", "Fake Delegate alpha 2", 11],
    ]) {
      await db.doc(`${pp}/captured_photos/${id}`).set({
        permissionId: "seed-fake-tas392-pp1", branchId: BRANCH_ID, branchName: BRANCH_NAME,
        monthKey: now.toISOString().slice(0, 7), delegateName: dName, delegateUID: dUid,
        companyName: "Fake Company Alpha", companyUID: CO, organizationUID: ORG,
        photoUrl: tmpl?.photoUrl ?? "", capturedAt: dayAt(0, h), comment: "صورة تجريبية TAS-393",
        location: new admin.firestore.GeoPoint(0, 0), ...tag,
      });
      console.log(`photo ${id}`);
    }
  }

  // One issued penalty and two notifications.
  await db.doc("penalties/seed-fake-tas393-pen-1").set({
    penaltyId: "seed-fake-tas393-pen-1", companyId: CO, companyUID: CO,
    companyName: "Fake Company Alpha", organizationId: ORG, organizationUID: ORG,
    createdById: "seed-fake-supervisor-alpha", createdByName: "Fake Supervisor alpha",
    createdByRole: "supervisor", title: "التواجد بدون تصريح (تجريبي TAS-393)",
    category: "PROTOCOL_BREACH", incidentDescription: "مخالفة تجريبية للرحلة",
    fineAmount: 100, currency: "EGP", status: "ISSUED", evidenceFiles: [],
    targetDelegateId: "seed-fake-del-alpha-3", targetDelegateName: "Fake Delegate alpha 3",
    branchName: BRANCH_NAME, isRepeated: false, isConfidential: false,
    createdAt: dayAt(-2, 10), issuedAt: dayAt(-2, 10), updatedAt: dayAt(-2, 10), ...tag,
  });
  for (const [id, type, title, body, read] of [
    ["seed-fake-tas393-notif-1", "task", "مهمة جديدة: مراجعة رف العروض",
      "اتسندتلك مهمة في Fake Branch Alpha.", false],
    ["seed-fake-tas393-notif-2", "announcement", "إعلان: جرد آخر الشهر",
      "الجرد يوم 30 نوفمبر من 8 الصبح.", true],
  ]) {
    await db.doc(`notifications/${id}`).set({
      delegateUid: MKT, organizationId: ORG, organizationUID: ORG, companyId: CO,
      companyUID: CO, type, title, body, message: body, isRead: read,
      createdAt: dayAt(0, 9), timestamp: dayAt(0, 9), deletedBy: [],
      createdBy: "seed-fake-supervisor-alpha", senderName: "Fake Supervisor alpha", ...tag,
    });
  }
  console.log("penalty + 2 notifications");
}

main().catch((e) => {
  console.error(`seed-marketing-journey-attendance: ${e.message}`);
  process.exit(1);
});
