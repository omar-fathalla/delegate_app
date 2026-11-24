/**
 * TAS-84: a company's own admin cannot change billing, counters, the
 * approval status or the chain link on its company doc (DevTools edits).
 * The org admin and global staff keep doing those. Fake data only.
 *
 * npm run test:rules:tas84
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, updateDoc, deleteDoc, serverTimestamp, increment} = require("firebase/firestore");

const ORG = "seed-fake-tas84-org";
const CO = "seed-fake-tas84-co";
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas84",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/admin-a"), {role: "company-admin", organizationUID: ORG, companyUID: CO, fake: true});
    await setDoc(doc(db, "users/orgadmin"), {role: "organization-admin", organizationUID: ORG, fake: true});
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}`), {
      name: "Fake", status: "Action Required", deferredPayment: 500, hasDeferredPayment: true,
      totalApprovedDelegates: 3, admins: 1, organizationUID: ORG, fake: true,
    });
  });
});
after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const co = (db) => doc(db, `organizations/${ORG}/companies/${CO}`);

describe("company admin on its own company doc", () => {
  test("cannot clear its debt", () => assertDeniedByRule(updateDoc(co(as("admin-a")), {deferredPayment: 0, hasDeferredPayment: false})));
  test("cannot bump counters", () => assertDeniedByRule(updateDoc(co(as("admin-a")), {totalApprovedDelegates: increment(10)})));
  test("cannot self-approve", () => assertDeniedByRule(updateDoc(co(as("admin-a")), {status: "Approved"})));
  test("cannot move chain", () => assertDeniedByRule(updateDoc(co(as("admin-a")), {organizationUID: "other-org"})));
  test("cannot create or delete company docs", async () => {
    await assertDeniedByRule(setDoc(doc(as("admin-a"), `organizations/${ORG}/companies/${CO}-new`), {name: "x"}));
    await assertDeniedByRule(deleteDoc(co(as("admin-a"))));
  });
  test("still updates its documents and resubmits (web updateCompanyDocuments$)", async () => {
    await assertSucceeds(updateDoc(co(as("admin-a")), {
      commercialRegisterNumber: "123", taxCardNumber: "456",
      documentUrls: {commercialRegister: "x", taxCard: "y"}, updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(co(as("admin-a")), {status: "Pending", updatedAt: serverTimestamp()}));
  });
});

describe("org admin keeps the billing and approval writes", () => {
  test("clears deferred payment and approves", async () => {
    await assertSucceeds(updateDoc(co(as("orgadmin")), {deferredPayment: 0, hasDeferredPayment: false, updatedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(co(as("orgadmin")), {totalApprovedDelegates: increment(1)}));
  });
});
