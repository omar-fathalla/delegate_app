/**
 * Emulator test (TAS-23): the users/{uid} claims sync and the claims backfill
 * against the Auth + Firestore emulators.
 *
 *   npm run test:e2e:claims-sync
 *   (bash scripts/emulators_exec.sh --only auth,firestore --project demo-tas23-claims \
 *      "node --test functions/test/staff_claims_sync.emulator.test.js")
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const live = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

const ORG = "seed-fake-tas23-org";
const CO = "seed-fake-tas23-co";
const CO2 = "seed-fake-tas23-co2";

test("sync trigger: grants only with membership, revokes on removal, never touches global or delegate claims", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas23-claims"});
  const {applyStaffClaimSync} = require("../lib/staff_claims_sync");
  const db = admin.firestore();
  const auth = admin.auth();
  const mk = async (uid, claims) => {
    await auth.createUser({uid, email: `${uid}@tashil-dev.test`}).catch(() => undefined);
    await auth.setCustomUserClaims(uid, claims || null);
  };
  const claims = async (uid) => (await auth.getUser(uid)).customClaims || {};
  const sync = (uid, before, after) => applyStaffClaimSync(db, auth, uid, before, after);

  // 1. Forged self-promotion: users doc says company-admin, no membership -> nothing granted.
  await mk("forger");
  const forged = {role: "company-admin", organizationUID: ORG, companyUID: CO};
  assert.equal((await sync("forger", {role: "delegate"}, forged)).result, "unverified");
  assert.deepEqual(await claims("forger"), {});

  // 2. HR promoted to company admin with a server membership -> granted, other keys kept.
  await mk("hr1", {role: "hr", orgId: ORG, organizationId: ORG, companyId: CO, mfaGraceUntil: 1});
  await db.doc(`organizations/${ORG}/companies/${CO}/members/hr1`).set({role: "company-admin", status: "active"});
  const hr = {role: "hr", organizationUID: ORG, companyUID: CO};
  assert.equal((await sync("hr1", hr, {...hr, role: "company-admin"})).result, "granted");
  assert.deepEqual(await claims("hr1"), {role: "company-admin", orgId: ORG, organizationId: ORG, companyId: CO, mfaGraceUntil: 1});

  // 3. Moved to another company without membership there -> staff claims removed (fail closed).
  assert.equal((await sync("hr1", {...hr, role: "company-admin"}, {...hr, role: "company-admin", companyUID: CO2})).result, "revoked");
  assert.deepEqual(await claims("hr1"), {mfaGraceUntil: 1});

  // 4. Demotion to delegate and doc deletion revoke.
  await mk("sup1", {role: "supervisor", orgId: ORG, organizationId: ORG, companyId: CO});
  const sup = {role: "supervisor", organizationUID: ORG, companyUID: CO};
  assert.equal((await sync("sup1", sup, {...sup, role: "delegate"})).result, "revoked");
  assert.deepEqual(await claims("sup1"), {});
  await mk("sup2", {role: "supervisor", orgId: ORG, organizationId: ORG, companyId: CO});
  assert.equal((await sync("sup2", sup, null)).result, "revoked");

  // 5. Unrelated edits do nothing, even when claims and doc differ.
  await mk("hr2", {role: "hr", orgId: ORG, organizationId: ORG, companyId: CO});
  assert.equal((await sync("hr2", {...hr, companyUID: ""}, {...hr, companyUID: "", displayName: "x"})).result, "noop");
  assert.equal((await claims("hr2")).role, "hr");

  // 6. Global and delegate claims are never touched; global roles never granted.
  await mk("sa1", {role: "super-admin"});
  assert.equal((await sync("sa1", {role: "super-admin"}, null)).result, "noop");
  assert.deepEqual(await claims("sa1"), {role: "super-admin"});
  await mk("del1", {role: "delegate", delegateId: "d1"});
  assert.equal((await sync("del1", {role: "delegate"}, forged)).result, "noop");
  assert.deepEqual(await claims("del1"), {role: "delegate", delegateId: "d1"});
  await mk("acc1");
  assert.equal((await sync("acc1", null, {role: "accountant"})).result, "noop");
  assert.deepEqual(await claims("acc1"), {});

  // 7. Org admin needs an org-admin membership in that chain.
  await mk("oa1");
  await db.doc(`organizations/${ORG}/members/oa1`).set({role: "org-admin", status: "active"});
  assert.equal((await sync("oa1", null, {role: "organization-admin", organizationUID: ORG})).result, "granted");
  assert.deepEqual(await claims("oa1"), {role: "organization-admin", orgId: ORG, organizationId: ORG, companyId: ""});

  // 8. No Auth user (e.g. a delegate doc without an account): nothing.
  assert.equal((await sync("ghost", null, forged)).result, "noop");
});

test("backfill: dry-run changes nothing, --apply sets confirmed rows with a backup, --rollback restores", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas23-claims"});
  const {run} = require("../scripts/backfill_staff_claims");
  const db = admin.firestore();
  const auth = admin.auth();
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "tas23-claims-"));
  const project = process.env.GCLOUD_PROJECT || "demo-tas23-claims";
  const user = async (uid, doc, claims) => {
    await auth.createUser({uid, email: `${uid}@tashil-dev.test`}).catch(() => undefined);
    await auth.setCustomUserClaims(uid, claims || null);
    await db.doc(`users/${uid}`).set(doc);
  };
  await user("bf-hr", {role: "company_hr", organizationUID: ORG, companyUID: CO});
  await db.doc(`organizations/${ORG}/companies/${CO}/members/bf-hr`).set({role: "hr"});
  await user("bf-mkt", {role: "marketing", organizationUID: ORG});
  await db.doc(`organizations/${ORG}/members/bf-mkt`).set({role: "marketing", status: "active"});
  await user("bf-forged", {role: "admin", organizationUID: ORG, companyUID: CO});
  await user("bf-acc", {role: "accountant"});
  await user("bf-oa", {role: "organization-admin", organizationUID: ORG}, {role: "organization-admin", organizationId: ORG, x: 1});
  await user("bf-del", {role: "delegate"}, {role: "delegate"});
  const allowFile = path.join(out, "allow.json");
  fs.writeFileSync(allowFile, JSON.stringify(["bf-acc"]));

  const quiet = () => undefined;
  await assert.rejects(run(["--apply"], {admin, log: quiet}), /--project/);
  await assert.rejects(run(["--project", "practice-firebase-72df1"], {admin, log: quiet}), /allow-prod-project/);

  const dry = await run(["--project", project, "--out", out, "--allow-file", allowFile], {admin, log: quiet});
  const act = Object.fromEntries(dry.rows.filter((r) => r.uid.startsWith("bf-")).map((r) => [r.uid, r.action]));
  assert.deepEqual(act, {"bf-hr": "set", "bf-mkt": "set", "bf-forged": "manual", "bf-acc": "set", "bf-oa": "set"});
  assert.deepEqual((await auth.getUser("bf-hr")).customClaims || {}, {}, "dry-run writes nothing");
  const report = fs.readFileSync(dry.reportFile, "utf8");
  assert.ok(!report.includes("@"), "no emails in the report");

  const res = await run(["--project", project, "--out", out, "--allow-file", allowFile, "--apply"], {admin, log: quiet});
  assert.equal(res.verified, res.done);
  assert.deepEqual((await auth.getUser("bf-hr")).customClaims, {role: "hr", orgId: ORG, organizationId: ORG, companyId: CO});
  assert.deepEqual((await auth.getUser("bf-mkt")).customClaims, {role: "marketing", orgId: ORG, organizationId: ORG, companyId: ""});
  assert.deepEqual((await auth.getUser("bf-acc")).customClaims, {role: "accountant", orgId: "", organizationId: "", companyId: ""});
  assert.deepEqual((await auth.getUser("bf-oa")).customClaims, {role: "organization-admin", orgId: ORG, organizationId: ORG, companyId: "", x: 1});
  assert.deepEqual((await auth.getUser("bf-forged")).customClaims || {}, {});
  assert.deepEqual((await auth.getUser("bf-del")).customClaims, {role: "delegate"});

  // A second dry-run is clean for the applied rows.
  const again = await run(["--project", project, "--out", out, "--allow-file", allowFile], {admin, log: quiet});
  assert.equal(again.rows.filter((r) => r.uid.startsWith("bf-") && r.action === "set").length, 0);

  // Rollback: conflict on a changed account unless --force, others restored.
  await auth.setCustomUserClaims("bf-mkt", {role: "marketing", orgId: ORG, organizationId: ORG, companyId: "", changed: true});
  const rb = await run(["--project", project, "--out", out, "--rollback", res.backupFile], {admin, log: quiet});
  assert.equal(rb.conflicts, 1);
  assert.deepEqual((await auth.getUser("bf-hr")).customClaims || {}, {});
  assert.deepEqual((await auth.getUser("bf-oa")).customClaims, {role: "organization-admin", organizationId: ORG, x: 1});
  assert.equal((await auth.getUser("bf-mkt")).customClaims.changed, true);
});
