/**
 * TAS-254: new delegates are registered under the base (free) chain from every
 * company; only super admins / tech support review those requests. The base
 * chain's organization admin must not read, list, edit or delete them. Other
 * chains' org admins keep their access to their own requests.
 * Fake data only.
 *
 * npm run test:rules:tas254
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where} = require("firebase/firestore");

const BASE = "seed-fake-base-chain";
const PAID = "seed-fake-paid-chain";
const CO_A = "seed-fake-tas254-co-a";

const users = {
  "base-oa": {role: "organizationAdmin", organizationUID: BASE},
  "paid-oa": {role: "organizationAdmin", organizationUID: PAID},
  "sa": {role: "super-admin"},
  "sup-a": {role: "supervisor", organizationUID: PAID, companyUID: CO_A},
};

const request = (org) => ({
  requestType: "new_delegate", status: "pending", organizationUID: org, organizationUIDs: [org],
  companyUID: CO_A, companyName: "fake", supervisorUid: "sup-a", fullName: "Fake Delegate",
  notes: "", fake: true,
});

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas254",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    await setDoc(doc(db, "config/subscriptions"), {freeChainOrgUids: [BASE]});
    await setDoc(doc(db, `organizations/${BASE}`), {name: "Base chain (fake)"});
    await setDoc(doc(db, `organizations/${PAID}`), {name: "Paid chain (fake)"});
    await setDoc(doc(db, "delegate_requests/req-base"), request(BASE));
    await setDoc(doc(db, "delegate_requests/req-base-del"), request(BASE));
    await setDoc(doc(db, "delegate_requests/req-paid"), request(PAID));
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const byOrg = (uid, org) => query(collection(as(uid), "delegate_requests"), where("organizationUID", "==", org));

describe("base chain org admin", () => {
  test("cannot read a request on the base chain", () =>
    assertFails(getDoc(doc(as("base-oa"), "delegate_requests/req-base"))));
  test("cannot list requests on the base chain", () =>
    assertFails(getDocs(byOrg("base-oa", BASE))));
  test("cannot edit notes on them", () =>
    assertFails(updateDoc(doc(as("base-oa"), "delegate_requests/req-base"), {notes: "x", updatedAt: new Date()})));
  test("cannot delete them", () =>
    assertFails(deleteDoc(doc(as("base-oa"), "delegate_requests/req-base-del"))));
});

describe("everyone else keeps their access", () => {
  test("another chain's org admin reads and lists its own requests", async () => {
    await assertSucceeds(getDoc(doc(as("paid-oa"), "delegate_requests/req-paid")));
    await assertSucceeds(getDocs(byOrg("paid-oa", PAID)));
  });
  test("another chain's org admin still cannot read base-chain requests", () =>
    assertFails(getDoc(doc(as("paid-oa"), "delegate_requests/req-base"))));
  test("super admin reads and lists base-chain requests", async () => {
    await assertSucceeds(getDoc(doc(as("sa"), "delegate_requests/req-base")));
    await assertSucceeds(getDocs(byOrg("sa", BASE)));
  });
  test("the requesting company's supervisor reads its base-chain request", () =>
    assertSucceeds(getDoc(doc(as("sup-a"), "delegate_requests/req-base"))));
  test("super admin deletes a base-chain request", () =>
    assertSucceeds(deleteDoc(doc(as("sa"), "delegate_requests/req-base-del"))));
});
