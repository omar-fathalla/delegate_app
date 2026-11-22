/**
 * TAS-73 (penalties): the penalties lists the app loads (penaltyListEventFor)
 * are allowed by the rules and stay inside the tenant, and an org-admin can
 * create a penalty now that the app writes organizationId. Fake data only.
 *
 * npm run test:rules:tas73-penalties
 */
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, setDoc, getDocs, collection, query, where} = require("firebase/firestore");

const ORG_A = "seed-fake-tas73p-org-a";
const ORG_B = "seed-fake-tas73p-org-b";
const CO_A1 = "seed-fake-tas73p-co-a1";
const CO_A2 = "seed-fake-tas73p-co-a2";
const CO_B1 = "seed-fake-tas73p-co-b1";

const staff = {
  "orgadmin-a": {role: "organization-admin", organizationUID: ORG_A},
  "mkt-a": {role: "marketing", organizationUID: ORG_A},
  "hr-a1": {role: "hr", organizationUID: ORG_A, companyUID: CO_A1},
  "acc-a1": {role: "accountant", organizationUID: ORG_A, companyUID: CO_A1},
  "cadmin-a1": {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A1},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas73-penalties",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    for (const [org, co] of [[ORG_A, CO_A1], [ORG_A, CO_A2], [ORG_B, CO_B1]]) {
      await setDoc(doc(db, `penalties/pen-${co}`), {
        companyId: co, organizationId: org, targetDelegateId: `del-${co}`,
        status: "issued", fineAmount: 50, fake: true,
      });
    }
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const byCompany = (db, co) => getDocs(query(collection(db, "penalties"), where("companyId", "==", co)));
const byOrg = (db, org) => getDocs(query(collection(db, "penalties"), where("organizationId", "==", org)));
const companies = (snap) => snap.docs.map((d) => d.data().companyId).sort();

describe("penalties lists (penaltyListEventFor)", () => {
  for (const uid of ["hr-a1", "acc-a1", "cadmin-a1"]) {
    test(`${uid} (${staff[uid].role}) lists its company`, async () => {
      const snap = await assertSucceeds(byCompany(as(uid), CO_A1));
      assert.deepStrictEqual(companies(snap), [CO_A1]);
    });
  }

  for (const uid of ["orgadmin-a", "mkt-a"]) {
    test(`${uid} (${staff[uid].role}, no company) lists its organization`, async () => {
      const snap = await assertSucceeds(byOrg(as(uid), ORG_A));
      assert.deepStrictEqual(companies(snap), [CO_A1, CO_A2].sort());
    });
  }
});

describe("penalty create (penaltyCreateOk)", () => {
  const create = (uid, id, companyId, organizationId) => setDoc(doc(as(uid), `penalties/${id}`), {
    companyId, companyName: "fake", ...(organizationId ? {organizationId} : {}),
    targetDelegateId: "del-x", status: "pendingBranchesMarketing", fineAmount: 10, fake: true,
  });

  test("org-admin creates in its own organization", async () => {
    await assertSucceeds(create("orgadmin-a", "pen-new-a2", CO_A2, ORG_A));
  });

  test("org-level marketing creates in its own organization", async () => {
    await assertSucceeds(create("mkt-a", "pen-new-mkt", CO_A1, ORG_A));
  });

  test("org-admin cannot create for another organization", async () => {
    await assertFails(create("orgadmin-a", "pen-new-b1", CO_B1, ORG_B));
  });

  test("org-admin cannot create without organizationId", async () => {
    await assertFails(create("orgadmin-a", "pen-new-noorg", CO_A2));
  });

  for (const uid of ["hr-a1", "acc-a1", "cadmin-a1"]) {
    test(`${uid} creates in its company, not in another`, async () => {
      await assertSucceeds(create(uid, `pen-own-${uid}`, CO_A1, ORG_A));
      await assertFails(create(uid, `pen-other-${uid}`, CO_A2, ORG_A));
    });
  }
});
