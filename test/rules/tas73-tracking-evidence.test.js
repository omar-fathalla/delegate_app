/**
 * TAS-73 (tracking, evidence, users lists): org-scoped staff (organization
 * admin and org-level marketing, no companyUID) can read the breadcrumbs of
 * a delegate in their organization and the penalty evidence of a company in
 * their organization; nothing outside it. Also the users lists the
 * marketing-management screen now sends. Fake data only.
 *
 * npm run test:rules:tas73-tracking
 */
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, setDoc, getDocs, collection, query, where, orderBy, limit} = require("firebase/firestore");
const {ref, uploadBytes, getBytes} = require("firebase/storage");

const ORG_A = "seed-fake-tas73t-org-a";
const ORG_B = "seed-fake-tas73t-org-b";
const CO_A1 = "seed-fake-tas73t-co-a1";
const CO_B1 = "seed-fake-tas73t-co-b1";

const staff = {
  "orgadmin-a": {role: "organization-admin", organizationUID: ORG_A},
  "mkt-a": {role: "marketing", organizationUID: ORG_A},
  "hr-a1": {role: "hr", organizationUID: ORG_A, companyUID: CO_A1},
  "cadmin-a1": {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A1},
  "orgadmin-b": {role: "organization-admin", organizationUID: ORG_B},
};

let env;
const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas73-tracking",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    storage: {rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    for (const [org, co] of [[ORG_A, CO_A1], [ORG_B, CO_B1]]) {
      await setDoc(doc(db, `organizations/${org}/companies/${co}`), {name: co, fake: true});
      await setDoc(doc(db, `delegate_tracking/del-${co}`), {
        companyUID: co, organizationUID: org, delegateUid: `del-${co}`, fake: true,
      });
      await setDoc(doc(db, `delegate_tracking/del-${co}/breadcrumbs/b1`), {
        latitude: 30, longitude: 31, timestamp: new Date("2026-11-22T08:00:00Z"), fake: true,
      });
      await uploadBytes(ref(ctx.storage(), `penalties/${co}/evidence/pen-1/seed.jpg`), bytes);
    }
  });
});

after(async () => env && env.cleanup());

const fs = (uid) => env.authenticatedContext(uid).firestore();
const st = (uid) => env.authenticatedContext(uid).storage();
const breadcrumbs = (db, co) => getDocs(query(
  collection(db, `delegate_tracking/del-${co}/breadcrumbs`), orderBy("timestamp", "desc"), limit(200),
));

describe("breadcrumbs (streamBreadcrumbs / getTodayBreadcrumbs)", () => {
  for (const uid of ["orgadmin-a", "mkt-a", "hr-a1", "cadmin-a1"]) {
    test(`${uid} (${staff[uid].role}) reads a delegate in its organization`, async () => {
      const snap = await assertSucceeds(breadcrumbs(fs(uid), CO_A1));
      assert.strictEqual(snap.size, 1);
    });
  }

  test("org-admin of another organization is denied", async () => {
    await assertFails(breadcrumbs(fs("orgadmin-b"), CO_A1));
  });

  test("company staff cannot read a delegate of another company", async () => {
    await assertFails(breadcrumbs(fs("hr-a1"), CO_B1));
  });
});

describe("penalty evidence storage (penalties/{co}/evidence)", () => {
  test("org-admin uploads and reads evidence of a company in its organization", async () => {
    await assertSucceeds(uploadBytes(ref(st("orgadmin-a"), `penalties/${CO_A1}/evidence/pen-2/a.jpg`), bytes));
    await assertSucceeds(getBytes(ref(st("orgadmin-a"), `penalties/${CO_A1}/evidence/pen-1/seed.jpg`)));
  });

  test("org-level marketing reads evidence in its organization", async () => {
    await assertSucceeds(getBytes(ref(st("mkt-a"), `penalties/${CO_A1}/evidence/pen-1/seed.jpg`)));
  });

  test("org-admin cannot touch evidence of another organization's company", async () => {
    await assertFails(uploadBytes(ref(st("orgadmin-a"), `penalties/${CO_B1}/evidence/pen-3/x.jpg`), bytes));
    await assertFails(getBytes(ref(st("orgadmin-a"), `penalties/${CO_B1}/evidence/pen-1/seed.jpg`)));
  });

  test("company staff keep their company only", async () => {
    await assertSucceeds(getBytes(ref(st("hr-a1"), `penalties/${CO_A1}/evidence/pen-1/seed.jpg`)));
    await assertFails(getBytes(ref(st("hr-a1"), `penalties/${CO_B1}/evidence/pen-1/seed.jpg`)));
  });
});

describe("users lists of the marketing-management screen", () => {
  const usersBy = (db, field, value) => getDocs(query(collection(db, "users"), where(field, "==", value)));

  test("org-admin lists the users of its organization", async () => {
    const snap = await assertSucceeds(usersBy(fs("orgadmin-a"), "organizationUID", ORG_A));
    assert.ok(snap.docs.every((d) => d.data().organizationUID === ORG_A));
  });

  test("company admin lists the users of its company", async () => {
    const snap = await assertSucceeds(usersBy(fs("cadmin-a1"), "companyUID", CO_A1));
    assert.ok(snap.docs.every((d) => d.data().companyUID === CO_A1));
  });
});
