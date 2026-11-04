/**
 * Emulator test for the P0 scripts (purge, revoke+reset, role counts).
 *   firebase emulators:exec --only auth,firestore --project demo-p0-scripts \
 *     "node --test functions/scripts/p0-scripts.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const common = require("./p0-common");
const {purge} = require("./purge-password-fields");
const {run} = require("./revoke-and-force-reset");
const {counts} = require("./role-counts");

const live = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

test("guards: allow-list, normalized; prod and look-alikes refused", () => {
  const t = (...a) => common.assertTarget(common.parseArgs(a));
  assert.throws(() => t(), /required/);
  for (const p of ["practice-firebase-72df1", "Practice-Firebase-72df1", " practice-firebase-72df1 ",
    "projects/practice-firebase-72df1", "123456789012", "tashil-prod", "tashil-dev2", "demo-", "other"]) {
    assert.throws(() => t("--project", p, "--apply"), /allow-list|required/, p);
  }
  assert.equal(t("--project=tashil-dev"), "tashil-dev");
  assert.equal(t("--project", " Tashil-Dev "), "tashil-dev");
  assert.equal(t("--project", "projects/tashil-dev"), "tashil-dev");
  assert.equal(t("--project", "demo-p0-scripts"), "demo-p0-scripts");
  assert.throws(() => t("--project", "practice-firebase-72df1", "--allow-prod-project=tashil-dev"), /allow-list/);
  assert.equal(t("--project", "practice-firebase-72df1", "--allow-prod-project=practice-firebase-72df1"), "practice-firebase-72df1");
  assert.equal(common.resetPriority("super_admin"), 0);
  assert.equal(common.resetPriority("hr"), 1);
  assert.equal(common.resetPriority("delegate"), -1);
});

test("purge, revoke+reset and role counts on emulators", {skip: !live}, async () => {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-p0-scripts"});
  const db = admin.firestore(); const auth = admin.auth();
  await auth.createUser({uid: "sa", email: "sa@e.test"});
  await auth.createUser({uid: "hr", email: "hr@e.test"});
  await db.doc("users/sa").set({role: "super-admin", email: "sa@e.test", password: "x"});
  await db.doc("users/hr").set({role: "hr", email: "hr@e.test", temporaryPassword: "y"});
  await db.doc("users/d1").set({role: "delegate", phoneNumber: "010"});

  const dry = await purge(db, false);
  assert.equal(dry.withSecret, 2); assert.equal(dry.updated, 0);
  assert.equal((await db.doc("users/sa").get()).get("password"), "x");
  const ap = await purge(db, true);
  assert.equal(ap.updated, 2);
  assert.equal((await purge(db, false)).withSecret, 0);

  const before = (await auth.getUser("sa")).tokensValidAfterTime;
  const dr = await run(db, auth, {apply: false, superOnly: false});
  assert.deepEqual([dr.targets, dr.superAdmins, dr.revoked], [2, 1, 0]);
  const so = await run(db, auth, {apply: true, superOnly: true});
  assert.deepEqual([so.targets, so.revoked, so.resetQueued], [1, 1, 1]);
  assert.notEqual((await auth.getUser("sa")).tokensValidAfterTime, before);
  assert.equal((await db.doc("users/hr").get()).get("requireReLogin"), undefined);
  assert.equal((await db.collection("mail").get()).size, 1);

  assert.deepEqual(await counts(db), {total: 3, byRole: {"super-admin": 1, "hr": 1, "delegate": 1}});
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});
