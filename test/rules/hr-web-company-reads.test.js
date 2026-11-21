/**
 * HR web follow-ups (User Test on 691b417): company supervisors and HR open
 * «مسير الرواتب والعمولات» (user_wallets companyUID list) and
 * «الصور والزيارات الميدانية» (captured_photos collection-group companyUID
 * list) without a permission error, see only their own company, and HR lists
 * only the penalties issued to them. Fake data only.
 *
 * npm run test:rules:hr-web
 */
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("./_rules_testing");
const {
  doc, getDoc, getDocs, setDoc, updateDoc, collection, collectionGroup, query, where,
} = require("firebase/firestore");

const ORG = "seed-fake-hr-org";
const ALPHA = "seed-fake-co-alpha";
const BETA = "seed-fake-co-beta";

const staff = {
  "hr-004": {role: "hr", companyUID: ALPHA, phoneNumber: "01000000004"},
  "sup-005": {role: "supervisor", companyUID: ALPHA, phoneNumber: "01000000005"},
  "hr-006": {role: "hr", companyUID: ALPHA, phoneNumber: "01000000006"},
  "csup-027": {role: "company_supervisor", companyUID: BETA, phoneNumber: "01000000027"},
  "chr-029": {role: "company-hr", companyUID: ALPHA, phoneNumber: "01000000029"},
  "hr-beta-015": {role: "hr", companyUID: BETA, phoneNumber: "01000000015"},
  "mkt-007": {role: "marketing", companyUID: ALPHA, phoneNumber: "01000000007"},
  "bm-008": {role: "branches_marketing", companyUID: ALPHA, phoneNumber: "01000000008"},
  "hr-nocompany": {role: "hr", phoneNumber: "01000000031"},
};

const companyOf = (uid) => staff[uid].companyUID;
const otherCompany = (uid) => (companyOf(uid) === ALPHA ? BETA : ALPHA);
const HR_AND_SUPERVISORS = ["hr-004", "sup-005", "hr-006", "csup-027", "chr-029"];

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-hr-web-reads",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, organizationUID: ORG, fake: true});
    }
    for (const co of [ALPHA, BETA]) {
      await setDoc(doc(db, `organizations/${ORG}/companies/${co}`), {name: co, fake: true});
      await setDoc(doc(db, `user_wallets/wallet-${co}`), {companyUID: co, baseSalary: 4000, fake: true});
      const perm = `organizations/${ORG}/companies/${co}/photo_permissions/perm-${co}`;
      await setDoc(doc(db, perm), {companyUID: co, organizationUID: ORG, status: "approved", fake: true});
      await setDoc(doc(db, `${perm}/captured_photos/photo-${co}`), {
        companyUID: co, organizationUID: ORG, delegateUID: `del-${co}`, branchName: "fake-branch", fake: true,
      });
    }
    const penalty = (id, companyId, targetDelegateId) => setDoc(doc(db, `penalties/${id}`), {
      companyId, organizationId: ORG, targetDelegateId, status: "issued", fineAmount: 50, fake: true,
    });
    await penalty("pen-hr006-uid", ALPHA, "hr-006");
    await penalty("pen-hr006-phone", ALPHA, "01000000006");
    await penalty("pen-hr004", ALPHA, "hr-004");
    await penalty("pen-delegate-alpha", ALPHA, "del-alpha");
    await penalty("pen-hr006-beta", BETA, "hr-006");
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const delegateDb = (delegateId, companyId) => env.authenticatedContext(delegateId, {
  role: "delegate", delegateId, delegateIds: [delegateId], orgId: ORG, companyId,
}).firestore();

const walletList = (db, co) => getDocs(query(collection(db, "user_wallets"), where("companyUID", "==", co)));
const photoList = (db, co) => getDocs(query(collectionGroup(db, "captured_photos"), where("companyUID", "==", co)));
const ownPenalties = (db, co, subject) => getDocs(query(
  collection(db, "penalties"), where("companyId", "==", co), where("targetDelegateId", "==", subject),
));

describe("payroll: user_wallets company list", () => {
  for (const uid of HR_AND_SUPERVISORS) {
    test(`${uid} (${staff[uid].role}) lists only its company's wallets`, async () => {
      const snap = await assertSucceeds(walletList(as(uid), companyOf(uid)));
      assert.deepStrictEqual(snap.docs.map((d) => d.data().companyUID), [companyOf(uid)]);
    });

    test(`${uid} cannot list or get another company's wallets`, async () => {
      await assertFails(walletList(as(uid), otherCompany(uid)));
      await assertFails(getDoc(doc(as(uid), `user_wallets/wallet-${otherCompany(uid)}`)));
    });

    test(`${uid} cannot list wallets without a company filter`, async () => {
      await assertFails(getDocs(collection(as(uid), "user_wallets")));
    });

    test(`${uid} still cannot write a wallet`, async () => {
      await assertFails(updateDoc(doc(as(uid), `user_wallets/wallet-${companyOf(uid)}`), {baseSalary: 1}));
    });
  }

  for (const uid of ["mkt-007", "bm-008", "hr-nocompany"]) {
    test(`${uid} gets no wallet access from the HR rule`, async () => {
      await assertFails(walletList(as(uid), ALPHA));
    });
  }

  test("a delegate cannot list company wallets", async () => {
    await assertFails(walletList(delegateDb("del-alpha", ALPHA), ALPHA));
  });
});

describe("photos: captured_photos collection-group company list", () => {
  for (const uid of HR_AND_SUPERVISORS) {
    test(`${uid} (${staff[uid].role}) lists only its company's photos`, async () => {
      const snap = await assertSucceeds(photoList(as(uid), companyOf(uid)));
      assert.deepStrictEqual(snap.docs.map((d) => d.data().companyUID), [companyOf(uid)]);
    });

    test(`${uid} lists its company's photos filtered by branch`, async () => {
      await assertSucceeds(getDocs(query(
        collectionGroup(as(uid), "captured_photos"),
        where("companyUID", "==", companyOf(uid)),
        where("branchName", "==", "fake-branch"),
      )));
    });

    test(`${uid} cannot list another company's photos`, async () => {
      await assertFails(photoList(as(uid), otherCompany(uid)));
    });
  }

  test("an account without a company cannot list a company's photos", async () => {
    await assertFails(photoList(as("hr-nocompany"), ALPHA));
  });

  test("a delegate still lists its own photos by delegateUID", async () => {
    await assertSucceeds(getDocs(query(
      collectionGroup(delegateDb("del-alpha", ALPHA), "captured_photos"),
      where("delegateUID", "==", "del-alpha"),
    )));
  });
});

describe("penalties: HR sees only their own", () => {
  test("HR lists penalties issued to its uid", async () => {
    const snap = await assertSucceeds(ownPenalties(as("hr-006"), ALPHA, "hr-006"));
    assert.deepStrictEqual(snap.docs.map((d) => d.id), ["pen-hr006-uid"]);
  });

  test("HR lists penalties issued to its phone", async () => {
    const snap = await assertSucceeds(ownPenalties(as("hr-006"), ALPHA, "01000000006"));
    assert.deepStrictEqual(snap.docs.map((d) => d.id), ["pen-hr006-phone"]);
  });

  test("the own query never crosses companies", async () => {
    await assertFails(ownPenalties(as("hr-006"), BETA, "hr-006"));
    await assertFails(getDoc(doc(as("hr-006"), "penalties/pen-hr006-beta")));
  });

  test("HR cannot list every penalty (the old LoadAll path)", async () => {
    await assertFails(getDocs(collection(as("hr-006"), "penalties")));
  });

  test("HR cannot list by subject without the company filter", async () => {
    await assertFails(getDocs(query(collection(as("hr-006"), "penalties"), where("targetDelegateId", "==", "hr-006"))));
  });

  test("another company's HR cannot read alpha penalties", async () => {
    await assertFails(ownPenalties(as("hr-beta-015"), ALPHA, "hr-006"));
  });

  test("supervisors keep the company penalty list", async () => {
    const snap = await assertSucceeds(getDocs(query(collection(as("sup-005"), "penalties"), where("companyId", "==", ALPHA))));
    assert.strictEqual(snap.size, 4);
    await assertFails(getDocs(query(collection(as("sup-005"), "penalties"), where("companyId", "==", BETA))));
  });
});
