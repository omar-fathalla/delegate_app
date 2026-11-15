/**
 * Emulator test: orphan Firestore profile (no Auth) must not get a second profile.
 *
 *   firebase emulators:exec --only auth,firestore --project demo-create-tech-support \
 *     "node --test test/create_tech_support.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {runCreateTechSupport, parseArgs} = require("../create_tech_support");

const live = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;
const ORPHAN_EMAIL = "orphan-admin@example.test";
const PHONE = "01111111111";

test("apply refuses orphan company-admin (no Auth)", {skip: !live}, async () => {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-create-tech-support"});
  const db = admin.firestore();
  const auth = admin.auth();

  await db.doc("users/orphan-admin").set({
    role: "company-admin",
    email: ORPHAN_EMAIL,
    phoneNumber: PHONE,
    companyUID: "co-orphan",
  });

  const usersBefore = (await db.collection("users").get()).size;
  const mailBefore = (await db.collection("mail").get()).size;
  let authCount = 0;
  try {
    await auth.getUserByEmail(ORPHAN_EMAIL);
    authCount = 1;
  } catch (_) {
    authCount = 0;
  }
  assert.equal(authCount, 0);

  const args = parseArgs([
    "--project", "demo-create-tech-support",
    "--email", ORPHAN_EMAIL,
    "--phone", PHONE,
    "--apply",
  ]);

  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "demo-create-tech-support",
      db,
      auth,
    }),
    /refusing apply/,
  );

  const usersAfter = (await db.collection("users").get()).size;
  const mailAfter = (await db.collection("mail").get()).size;
  assert.equal(usersAfter, usersBefore);
  assert.equal(mailAfter, mailBefore);
  try {
    await auth.getUserByEmail(ORPHAN_EMAIL);
    assert.fail("expected no Auth user");
  } catch (_) {
  }

  await Promise.all(admin.apps.map((a) => a && a.delete()));
});