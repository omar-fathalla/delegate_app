/**
 * TAS-87: delegate stats docs (governorates chart, financial summary).
 *   organizations/{org}/stats/delegates                 chain totals
 *   organizations/{org}/companies/{co}/stats/delegates  company totals
 * Read by the staff who read those delegates; written by no client.
 * Every deny must come from a rule, not the 1000-expression budget.
 * Fake data only.
 *
 * npm run test:rules:tas87
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");

const ORG = "seed-fake-tas87-org";
const OTHER = "seed-fake-tas87-other";
const CO = "seed-fake-tas87-co";
const CO2 = "seed-fake-tas87-co2";
const ORG_STATS = `organizations/${ORG}/stats/delegates`;
const CO_STATS = `organizations/${ORG}/companies/${CO}/stats/delegates`;

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas87",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const users = {
      "sa": {role: "super-admin"},
      "tech": {role: "technical_support"},
      "oa": {role: "organization-admin", organizationUID: ORG},
      "mkt": {role: "marketing", organizationUID: ORG},
      "oa-other": {role: "organization-admin", organizationUID: OTHER},
      "ca": {role: "company-admin", organizationUID: ORG, companyUID: CO},
      "acc": {role: "accountant", organizationUID: ORG, companyUID: CO},
      "ca2": {role: "company-admin", organizationUID: ORG, companyUID: CO2},
      "del": {role: "delegate", organizationUID: ORG, companyUID: CO},
    };
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    await setDoc(doc(db, ORG_STATS), {total: 3, byCity: {"القاهرة": {Promoter: 3}}});
    await setDoc(doc(db, CO_STATS), {total: 2});
  });
});

after(async () => env && env.cleanup());

const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();

describe("chain stats doc", () => {
  test("global staff and this chain's org staff read it", async () => {
    for (const uid of ["sa", "tech", "oa", "mkt"]) await assertSucceeds(getDoc(doc(as(uid), ORG_STATS)));
  });
  test("another chain, company staff, delegates and guests are denied", async () => {
    for (const uid of ["oa-other", "ca", "acc", "ca2"]) await assertDeniedByRule(getDoc(doc(as(uid), ORG_STATS)));
    await assertDeniedByRule(getDoc(doc(as("del", {role: "delegate", orgId: ORG, companyId: CO}), ORG_STATS)));
    await assertDeniedByRule(getDoc(doc(env.unauthenticatedContext().firestore(), ORG_STATS)));
  });
});

describe("company stats doc", () => {
  test("global staff, this chain's org staff and this company's staff read it", async () => {
    for (const uid of ["sa", "tech", "oa", "mkt", "ca", "acc"]) await assertSucceeds(getDoc(doc(as(uid), CO_STATS)));
  });
  test("a sister company, another chain and delegates are denied", async () => {
    for (const uid of ["ca2", "oa-other"]) await assertDeniedByRule(getDoc(doc(as(uid), CO_STATS)));
    await assertDeniedByRule(getDoc(doc(as("del", {role: "delegate", orgId: ORG, companyId: CO}), CO_STATS)));
  });
});

describe("no client writes", () => {
  test("even a super admin cannot create, update or delete stats", async () => {
    for (const p of [ORG_STATS, CO_STATS]) {
      await assertDeniedByRule(setDoc(doc(as("sa"), p), {total: 999}));
      await assertDeniedByRule(updateDoc(doc(as("oa"), p), {total: 999}));
      await assertDeniedByRule(deleteDoc(doc(as("ca"), p)));
    }
    await assertDeniedByRule(setDoc(doc(as("sa"), `organizations/${ORG}/stats/new`), {total: 1}));
  });
  test("the trigger's event guard docs are closed too", async () => {
    await assertDeniedByRule(getDoc(doc(as("sa"), "_delegate_stats_events/e1")));
    await assertDeniedByRule(setDoc(doc(as("sa"), "_delegate_stats_events/e1"), {x: 1}));
  });
});
