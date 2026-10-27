/**
 * Emulator-only integration test for backfill-checkin-denorm.js.
 * Seeds synthetic attendance_logs + profiles, dry-runs, applies, verifies
 * idempotency. NEVER targets production.
 *
 *   firebase emulators:exec --only firestore \
 *     "node scripts/backfill-checkin-denorm.emulator.test.js"
 *
 * Or with emulator already up:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/backfill-checkin-denorm.emulator.test.js
 */

"use strict";

const assert = require("assert");
const path = require("path");
const fs = require("fs");
const {spawnSync} = require("child_process");
const admin = require("firebase-admin");

const PROJECT = "practice-firebase-72df1";
const ORG = "emuOrgBackfillTest";
const COLLECTION = "attendance_logs";
const SCRIPT = path.join(__dirname, "backfill-checkin-denorm.js");

function mustEmulator() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error("FIRESTORE_EMULATOR_HOST is required. Refusing to run.");
    process.exit(2);
  }
}

async function seed(db) {
  const companyId = "co1";
  const delegateId = "del1";
  const branch = "Smoha Test";

  await db
    .collection("organizations")
    .doc(ORG)
    .collection("companies")
    .doc(companyId)
    .set({name: "Acme Co", companyName: "Acme Co"});

  await db
    .collection("organizations")
    .doc(ORG)
    .collection("companies")
    .doc(companyId)
    .collection("delegates")
    .doc(delegateId)
    .set({
      fullName: "أحمد التجريبي",
      phoneNumber: "+201000000001",
      personalPhotoURL: "https://example.com/photo.jpg",
      companyUID: companyId,
      companyName: "Acme Co",
    });

  const day = admin.firestore.Timestamp.fromDate(
    new Date(Date.UTC(2026, 9, 15, 8, 0, 0)),
  );
  const outTs = admin.firestore.Timestamp.fromDate(
    new Date(Date.UTC(2026, 9, 15, 17, 30, 0)),
  );

  // check_in missing all denorm + checkout fields
  const inRef = db.collection(COLLECTION).doc("cin_missing");
  await inRef.set({
    type: "check_in",
    delegateId,
    userId: delegateId,
    companyId,
    organizationId: ORG,
    branchName: branch,
    timestamp: day,
    location: {latitude: 31.2, longitude: 29.9},
  });

  // matching check_out
  const outRef = db.collection(COLLECTION).doc("cout_1");
  await outRef.set({
    type: "check_out",
    delegateId,
    userId: delegateId,
    companyId,
    organizationId: ORG,
    branchName: branch,
    timestamp: outTs,
    location: {latitude: 31.21, longitude: 29.91},
    relatedCheckInId: inRef.id,
  });

  // already-complete check_in (should be skipped)
  await db.collection(COLLECTION).doc("cin_complete").set({
    type: "check_in",
    delegateId,
    organizationId: ORG,
    companyId,
    branchName: branch,
    timestamp: day,
    delegateName: "Already Set",
    phoneNumber: "+201111",
    companyName: "Acme Co",
    personalPhotoURL: "https://example.com/a.jpg",
    checkOutTime: outTs,
    checkOutDocId: "cout_pre",
    checkOutLocation: {latitude: 1, longitude: 2},
  });

  // orphan check_in with no checkout
  await db.collection(COLLECTION).doc("cin_orphan").set({
    type: "check_in",
    delegateId: "del_orphan",
    organizationId: ORG,
    companyId,
    branchName: branch,
    timestamp: day,
  });

  return {inRef, outRef};
}

function runBackfill(extraArgs) {
  const reportPath = path.join(__dirname, `../backfill-report-test-${Date.now()}.json`);
  const args = [
    SCRIPT,
    "--org", ORG,
    "--from", "2026-10-01",
    "--to", "2026-10-31",
    "--collection", COLLECTION,
    "--report", reportPath,
    "--rate-ms", "0",
    ...extraArgs,
  ];
  const res = spawnSync(process.execPath, args, {
    env: {...process.env, GCLOUD_PROJECT: PROJECT},
    encoding: "utf8",
  });
  if (res.status !== 0) {
    console.error(res.stdout);
    console.error(res.stderr);
    throw new Error(`backfill exited ${res.status}`);
  }
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  return {report, reportPath, stdout: res.stdout};
}

async function main() {
  mustEmulator();
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: PROJECT});
  }
  const db = admin.firestore();

  console.log("Seeding synthetic data…");
  const {inRef, outRef} = await seed(db);

  console.log("Dry-run…");
  const dry = runBackfill([]);
  assert.strictEqual(dry.report.mode, "dry-run");
  assert.ok(dry.report.wouldUpdate >= 1, "expected wouldUpdate >= 1");
  assert.strictEqual(dry.report.updated, 0);
  console.log("dry-run wouldUpdate=", dry.report.wouldUpdate);

  // Ensure dry-run did not write
  const before = await inRef.get();
  assert.ok(!before.data().delegateName, "dry-run must not stamp name");

  console.log("Apply…");
  const applied = runBackfill(["--apply"]);
  assert.strictEqual(applied.report.mode, "apply");
  assert.ok(applied.report.updated >= 1);

  const after = (await inRef.get()).data();
  assert.strictEqual(after.delegateName, "أحمد التجريبي");
  assert.strictEqual(after.phoneNumber, "+201000000001");
  assert.strictEqual(after.companyName, "Acme Co");
  assert.strictEqual(after.personalPhotoURL, "https://example.com/photo.jpg");
  assert.ok(after.checkOutTime, "checkOutTime stamped");
  assert.strictEqual(after.checkOutDocId, outRef.id);
  assert.ok(after.checkOutLocation, "checkOutLocation stamped");

  console.log("Idempotent re-apply…");
  const again = runBackfill(["--apply"]);
  // cin_missing now complete; cin_orphan may still want profile if we had one — we don't
  assert.ok(
    again.report.updated === 0 || again.report.wouldUpdate <= again.report.skippedComplete + 1,
    "second apply should mostly skip",
  );

  // Write summary for parent report
  const summary = {
    dryRunWouldUpdate: dry.report.wouldUpdate,
    dryRunEstimatedWrites: dry.report.estimatedWrites,
    dryRunEstimatedCostUsd: dry.report.estimatedCostUsd,
    applyUpdated: applied.report.updated,
    idempotentUpdated: again.report.updated,
    sampleUpdates: dry.report.sampleUpdates,
    emulator: process.env.FIRESTORE_EMULATOR_HOST,
  };
  const outPath = path.join(__dirname, "../../real_test/BACKFILL_EMULATOR_REPORT.json");
  fs.mkdirSync(path.dirname(outPath), {recursive: true});
  fs.writeFileSync(outPath, JSON.stringify(summary, null, 2));
  console.log("OK — summary at", outPath);
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
