/**
 * onStaffUserPhonesClaimSync + backfill-staff-phones-claim against the Auth +
 * Firestore emulators (handlers run in-process via the v1 .run()). Minted
 * claims are then replayed through firestore.rules: an HR user in company A
 * that copies a company B phone must read 0 company B notifications.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const admin = require("../../functions/node_modules/firebase-admin");
const {Change} = require("../../functions/node_modules/firebase-functions");
const {initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {collection, doc, getDoc, getDocs, limit, query, where} = require("firebase/firestore");

const ROOT = path.resolve(__dirname, "../..");
const ORG = "o1";
const CO_A = "coA";
const CO_B = "coB";

let fn; let db; let testEnv; let backfill; let variants;

const victimPhones = {
  a: "01055500003", // delegates.phone only
  b: "01055500004", // delegates.phoneNumber "+20 105 550 0004"
  c: "01055500005", // users.mobileNumber only
  d: "01055500006", // users.phone "0020 105-550-0006"
  e: "01055500007", // delegates.mobileNumber, stored as a number
};

async function seedVictims() {
  const dB = (id) => db.doc(`organizations/${ORG}/companies/${CO_B}/delegates/${id}`);
  await dB("dlgA").set({fullName: "A", companyUID: CO_B, phone: victimPhones.a});
  await dB("dlgB").set({fullName: "B", companyUID: CO_B, phoneNumber: "+20 105 550 0004"});
  await db.doc("users/staffC").set({role: "supervisor", companyUID: CO_B, organizationUID: ORG,
    mobileNumber: victimPhones.c});
  await db.doc("users/staffD").set({role: "hr", companyUID: CO_B, organizationUID: ORG,
    phone: "0020 105-550-0006"});
  await dB("dlgE").set({fullName: "E", companyUID: CO_B, mobileNumber: 1055500007});
  for (const [key, phone] of Object.entries(victimPhones)) {
    for (const v of [phone, "+20" + phone.substring(1)]) {
      await db.collection("notifications").doc(`victim_${key}_${v.replace("+", "p")}`).set({
        delegateUid: `phone_${v}`, phoneNumber: v, title: `coB-${key}`,
        companyId: CO_B, organizationId: ORG, isRead: false, deletedBy: [],
        createdAt: admin.firestore.Timestamp.now(),
      });
    }
  }
}

async function staffUser(uid, phoneNumber, companyUID = CO_A) {
  await admin.auth().createUser({uid, email: `${uid}@t.test`, emailVerified: true});
  const data = {role: "hr", companyUID, organizationUID: ORG, email: `${uid}@t.test`, phoneNumber};
  await runTrigger(uid, data);
}

async function runTrigger(uid, data) {
  const ref = db.doc(`users/${uid}`);
  const before = await ref.get();
  await ref.set(data);
  const after = await ref.get();
  await fn.onStaffUserPhonesClaimSync.run(Change.fromObjects(before, after), {params: {uid}});
}

async function claimsOf(uid) {
  return (await admin.auth().getUser(uid)).customClaims || {};
}

function staffDb(uid, claims) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@t.test`, email_verified: true,
    firebase: {sign_in_provider: "password"}, ...claims,
  }).firestore();
}

/** Every bell read shape for `phone`, counting only company B docs that come back. */
async function companyBReads(sdb, phone) {
  let n = 0;
  const shapes = variants(phone).flatMap((v) => [
    ["delegateUid", `phone_${v}`], ["delegateUid", v], ["phoneNumber", v],
  ]);
  for (const [field, value] of shapes) {
    try {
      const snap = await getDocs(query(collection(sdb, "notifications"), where(field, "==", value), limit(30)));
      n += snap.docs.filter((d) => d.data().companyId === CO_B).length;
    } catch (e) {
      assert.match(String(e.code || e.message), /permission-denied/i);
    }
  }
  const ids = (await db.collection("notifications").where("companyId", "==", CO_B).get()).docs
    .filter((d) => d.data().title.endsWith(Object.keys(victimPhones).find((k) => victimPhones[k] === phone)))
    .map((d) => d.id);
  for (const id of ids) {
    try {
      if ((await getDoc(doc(sdb, "notifications", id))).exists()) n += 1;
    } catch (e) {
      assert.match(String(e.code || e.message), /permission-denied/i);
    }
  }
  return n;
}

test.before(async () => {
  fn = require("../../functions/lib/index.js");
  backfill = require("../../functions/scripts/backfill-staff-phones-claim.js");
  const login = require("../../functions/lib/delegate_login_logic.js");
  variants = (p) => login.phoneQueryVariants(login.normalizePhone(p));
  db = admin.firestore();
  testEnv = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT,
    firestore: {rules: fs.readFileSync(path.join(ROOT, "firestore.rules"), "utf8")},
  });
  await seedVictims();
});

test.after(async () => {
  await testEnv.cleanup();
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

test("probe is not vacuous: a forced victim phones claim reads company B", async () => {
  await db.doc("users/forced").set({role: "hr", companyUID: CO_A, organizationUID: ORG});
  for (const phone of Object.values(victimPhones)) {
    const n = await companyBReads(staffDb("forced", {phones: variants(phone)}), phone);
    assert.ok(n > 0, `forced claim for ${phone} should read company B`);
  }
});

test("control: unique phone is minted and reads its own notification", async () => {
  await db.collection("notifications").doc("own_hrOk").set({
    delegateUid: "phone_01077700007", phoneNumber: "01077700007", title: "own",
    companyId: CO_A, organizationId: ORG, isRead: false, deletedBy: [],
    createdAt: admin.firestore.Timestamp.now(),
  });
  await staffUser("hrOk", "010 7770 0007");
  const claims = await claimsOf("hrOk");
  assert.deepEqual(claims.phones, variants("01077700007"));
  const snap = await getDocs(query(collection(staffDb("hrOk", claims), "notifications"),
    where("delegateUid", "==", "phone_01077700007"), limit(5)));
  assert.equal(snap.size, 1);
});

// [case, victim key, phone the company A HR user writes on their own users doc]
const attacks = [
  ["a: victim phone only in delegates.phone", "a", "+20 105 550 0003"],
  ["b: victim delegates.phoneNumber stored with spaces", "b", "01055500004"],
  ["c: victim phone only in users.mobileNumber", "c", "01055500005"],
  ["d: victim users.phone stored as 0020 with spaces/dashes", "d", "1055500006"],
  ["e: victim delegates.mobileNumber stored as a number", "e", "01055500007"],
];

for (const [name, key, written] of attacks) {
  test(`trigger ${name}: no mint, old claim cleared, 0 company B reads`, async () => {
    const uid = `hrAtk_${key}`;
    await staffUser(uid, `0109990000${key.charCodeAt(0) % 10}`);
    assert.ok((await claimsOf(uid)).phones, "own phone minted first");
    await runTrigger(uid, {role: "hr", companyUID: CO_A, organizationUID: ORG,
      email: `${uid}@t.test`, phoneNumber: written});
    const claims = await claimsOf(uid);
    assert.equal(claims.phones, undefined);
    assert.equal(await companyBReads(staffDb(uid, claims), victimPhones[key]), 0);
  });
}

test("trigger prefers the verified Auth phone over users.phoneNumber", async () => {
  await admin.auth().createUser({uid: "hrAuthPh", email: "hrAuthPh@t.test", phoneNumber: "+201088800008"});
  await runTrigger("hrAuthPh", {role: "hr", companyUID: CO_A, organizationUID: ORG,
    phoneNumber: victimPhones.a});
  assert.deepEqual((await claimsOf("hrAuthPh")).phones, variants("01088800008"));
});

test("trigger with no Auth user writes nothing and does not throw", async () => {
  await runTrigger("noAuthYet", {role: "hr", companyUID: CO_A, organizationUID: ORG, phoneNumber: "01066600006"});
  await assert.rejects(admin.auth().getUser("noAuthYet"));
});

test("backfill: same collision rules, 0 company B reads, unique phones minted", async () => {
  const seeded = {
    bfA: victimPhones.a, bfB: "+20 105 550 0004", bfC: victimPhones.c,
    bfD: victimPhones.d, bfE: victimPhones.e, bfOk: "01044400004",
  };
  for (const [uid, phoneNumber] of Object.entries(seeded)) {
    await admin.auth().createUser({uid, email: `${uid}@t.test`});
    await admin.auth().setCustomUserClaims(uid, {phones: ["stale"]});
    await db.doc(`users/${uid}`).set({role: "hr", companyUID: CO_A, organizationUID: ORG, phoneNumber});
  }
  const dry = await backfill.runStaffPhonesBackfill(db, admin.auth(), {apply: false});
  assert.equal((await claimsOf("bfA")).phones[0], "stale", "dry-run writes nothing");
  assert.ok(dry.skippedCollision >= 5);

  const counts = await backfill.runStaffPhonesBackfill(db, admin.auth(), {apply: true});
  assert.ok(counts.applied >= 6);
  for (const [uid, key] of [["bfA", "a"], ["bfB", "b"], ["bfC", "c"], ["bfD", "d"], ["bfE", "e"]]) {
    const claims = await claimsOf(uid);
    assert.equal(claims.phones, undefined, uid);
    assert.equal(await companyBReads(staffDb(uid, claims), victimPhones[key]), 0, uid);
  }
  assert.deepEqual((await claimsOf("bfOk")).phones, variants("01044400004"));
  assert.ok(counts.missingAuthUser >= 1, "users doc without an Auth user is counted, not minted");
});
