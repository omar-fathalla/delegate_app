/**
 * Emulator tests: orphan Firestore profile must not get a second profile.
 *
 *   firebase emulators:exec --only auth,firestore --project demo-create-tech-support \
 *     "node --test test/create_tech_support.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {runCreateTechSupport, parseArgs, normalizeLookupEmail} = require("../create_tech_support");

const live = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;
const ORPHAN_EMAIL = "orphan-admin@example.test";
const PHONE = "01111111111";

/** @param {FirebaseFirestore.Firestore} db @param {import("firebase-admin").auth.Auth} auth */
async function countAuthForEmail(auth, email) {
  try {
    await auth.getUserByEmail(email);
    return 1;
  } catch (err) {
    assert.ok(err);
    return 0;
  }
}

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
  assert.equal(await countAuthForEmail(auth, ORPHAN_EMAIL), 0);

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

  assert.equal((await db.collection("users").get()).size, usersBefore);
  assert.equal((await db.collection("mail").get()).size, mailBefore);
  assert.equal(await countAuthForEmail(auth, ORPHAN_EMAIL), 0);

  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

test("apply refuses orphan when Firestore email casing differs from CLI", {skip: !live}, async () => {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-create-tech-support"});
  const db = admin.firestore();
  const auth = admin.auth();

  const storedEmail = " User@X.COM ";
  await db.doc("users/orphan-admin").set({
    role: "company-admin",
    email: storedEmail,
    phoneNumber: PHONE,
    companyUID: "co-orphan",
  });

  const args = parseArgs([
    "--project", "demo-create-tech-support",
    "--email", "user@x.com",
    "--phone", PHONE,
    "--apply",
  ]);

  const usersBefore = (await db.collection("users").get()).size;
  const mailBefore = (await db.collection("mail").get()).size;

  await assert.rejects(
    () => runCreateTechSupport(args, {project: "demo-create-tech-support", db, auth}),
    /refusing apply/,
  );

  assert.equal((await db.collection("users").get()).size, usersBefore);
  assert.equal((await db.collection("mail").get()).size, mailBefore);

  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

test("apply refuses messy stored email with different phone (full scan)", {skip: !live}, async () => {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-create-tech-support"});
  const db = admin.firestore();
  const auth = admin.auth();

  const storedEmail = `\u00A0User\u200B@X.COM.\u00A0`;
  const storedPhone = "02222222222";
  const cliEmail = "user@x.com";
  const cliPhone = "01111111111";

  assert.equal(normalizeLookupEmail(storedEmail), normalizeLookupEmail(cliEmail));

  await db.doc("users/orphan-email-phone-mismatch").set({
    role: "company-admin",
    email: storedEmail,
    phoneNumber: storedPhone,
    companyUID: "co-orphan",
  });

  const usersBefore = (await db.collection("users").get()).size;
  const mailBefore = (await db.collection("mail").get()).size;
  assert.equal(await countAuthForEmail(auth, cliEmail), 0);

  const args = parseArgs([
    "--project", "demo-create-tech-support",
    "--email", cliEmail,
    "--phone", cliPhone,
    "--apply",
  ]);

  await assert.rejects(
    () => runCreateTechSupport(args, {project: "demo-create-tech-support", db, auth}),
    /refusing apply/,
  );

  assert.equal((await db.collection("users").get()).size, usersBefore);
  assert.equal((await db.collection("mail").get()).size, mailBefore);
  assert.equal(await countAuthForEmail(auth, cliEmail), 0);

  const snap = await db.doc("users/orphan-email-phone-mismatch").get();
  assert.equal(snap.get("role"), "company-admin");
  assert.equal(snap.get("phoneNumber"), storedPhone);

  await Promise.all(admin.apps.map((a) => a && a.delete()));
});