/**
 * TAS-402 (user decision 2026-11-27): branch marketing (role `marketing`)
 * may not delete a delegate's field photo (nested captured_photos), while the
 * roles that could before still can. Fake data only.
 *
 * npm run test:rules:tas402-photo-delete
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, setDoc, deleteDoc} = require("firebase/firestore");

const ORG = "seed-fake-tas402-org";
const CO = "seed-fake-tas402-co";
const PERM = `organizations/${ORG}/companies/${CO}/photo_permissions/perm-1`;

const staff = {
  "mkt": {role: "marketing", organizationUID: ORG},
  "mkt-co": {role: "marketing", organizationUID: ORG, companyUID: CO},
  "mktpromo": {role: "marketing_promotion", organizationUID: ORG},
  "orgadmin": {role: "organization-admin", organizationUID: ORG},
  "sup": {role: "supervisor", organizationUID: ORG, companyUID: CO},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas402-photo-delete",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}`), {name: CO, fake: true});
    await setDoc(doc(db, PERM), {companyUID: CO, organizationUID: ORG, status: "approved", fake: true});
  });
});

after(async () => env && env.cleanup());

const seedPhoto = async (id) => env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), `${PERM}/captured_photos/${id}`), {
    companyUID: CO, organizationUID: ORG, delegateUID: "del-1", fake: true,
  });
});
const del = (uid, id) => deleteDoc(doc(env.authenticatedContext(uid).firestore(), `${PERM}/captured_photos/${id}`));

describe("captured_photos delete (TAS-402)", () => {
  test("branch marketing (chain scope) cannot delete a field photo", async () => {
    await seedPhoto("p-mkt");
    await assertFails(del("mkt", "p-mkt"));
  });
  test("branch marketing with a company cannot delete either", async () => {
    await seedPhoto("p-mkt-co");
    await assertFails(del("mkt-co", "p-mkt-co"));
  });
  for (const uid of ["mktpromo", "orgadmin", "sup"]) {
    test(`${uid} keeps the delete`, async () => {
      await seedPhoto(`p-${uid}`);
      await assertSucceeds(del(uid, `p-${uid}`));
    });
  }
});
