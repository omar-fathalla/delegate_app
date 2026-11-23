/**
 * TAS-242: a delegate registered in two chains (orgIds/companyIds claims)
 * must read the supervisors of a company it belongs to in the second chain
 * (supervisor card after switching organization). A pair it is not in stays
 * denied, and a single-org delegate keeps the old behaviour. Fake data only.
 *
 * npm run test:rules:tas242
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("./_rules_testing");
const {collection, doc, getDoc, getDocs, query, setDoc, where} = require("firebase/firestore");

const MULTI = {
  role: "delegate", delegateId: "dm", delegateIds: ["dm"],
  orgId: "o1", companyId: "c1", orgIds: ["o1", "o2"], companyIds: ["c1", "c2"],
  firebase: {sign_in_provider: "custom"},
};
const SINGLE = {
  role: "delegate", delegateId: "ds", delegateIds: ["ds"], orgId: "o1", companyId: "c1",
  firebase: {sign_in_provider: "custom"},
};

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas242",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const put = (path, data) => setDoc(doc(db, path), {...data, fake: true});
    // dm is in o1/c1 and o2/c1 (same company, second chain). Not in o2/c2.
    await put("organizations/o1/companies/c1/delegates/dm", {position: "promoter"});
    await put("organizations/o2/companies/c1/delegates/dm", {position: "promoter"});
    await put("organizations/o2/companies/c1/delegates/sup", {position: "supervisor"});
    await put("organizations/o2/companies/c2/delegates/sup2", {position: "supervisor"});
    await put("organizations/o1/companies/c1/delegates/ds", {position: "promoter"});
  });
});
after(async () => env && env.cleanup());

const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();
const supervisors = (db, org, co) => query(
  collection(db, `organizations/${org}/companies/${co}/delegates`),
  where("position", "in", ["supervisor", "Supervisor", "مشرف"]),
);

describe("multi-org delegate", () => {
  test("lists supervisors in the second chain's company it belongs to", () =>
    assertSucceeds(getDocs(supervisors(as("dm", MULTI), "o2", "c1"))));
  test("reads a supervisor doc there", () =>
    assertSucceeds(getDoc(doc(as("dm", MULTI), "organizations/o2/companies/c1/delegates/sup"))));
  test("org x company pair it is not in stays denied", () =>
    assertFails(getDocs(supervisors(as("dm", MULTI), "o2", "c2"))));
  test("first chain still works", () =>
    assertSucceeds(getDocs(supervisors(as("dm", MULTI), "o1", "c1"))));
});

describe("single-org delegate unchanged", () => {
  test("own company lists", () =>
    assertSucceeds(getDocs(supervisors(as("ds", SINGLE), "o1", "c1"))));
  test("another chain denied", () =>
    assertFails(getDocs(supervisors(as("ds", SINGLE), "o2", "c1"))));
});
