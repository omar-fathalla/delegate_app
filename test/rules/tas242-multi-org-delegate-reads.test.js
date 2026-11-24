/**
 * TAS-242 + TAS-55: reads of other delegate documents by delegate tokens.
 *
 * TAS-55 (user decision 2026-11-24): a supervisor (its own copy in the
 * company has position supervisor) reads every delegate of that company; a
 * plain delegate (promoter) reads only its own document. The supervisor card
 * of a plain delegate comes from the getMySupervisorCards callable.
 *
 * TAS-242: a supervisor registered in two chains (orgIds/companyIds claims)
 * reads the delegates of a company it belongs to in the second chain. A pair
 * it is not in stays denied. Fake data only.
 *
 * npm run test:rules:tas242
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {collection, doc, getDoc, getDocs, query, setDoc, where} = require("firebase/firestore");

const token = (uid, extra) => ({
  role: "delegate", delegateId: uid, delegateIds: [uid], orgId: "o1", companyId: "c1",
  firebase: {sign_in_provider: "custom"}, ...extra,
});
const MULTI = {orgIds: ["o1", "o2"], companyIds: ["c1", "c2"]};

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas242",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const put = (path, data) => setDoc(doc(db, path), {
      nationalityID: "29001010000000", phoneNumber: "01000000000", ...data, fake: true,
    });
    // dm: promoter in o1/c1 and o2/c1. sm: supervisor in o1/c1 and o2/c1.
    await put("organizations/o1/companies/c1/delegates/dm", {position: "promoter"});
    await put("organizations/o2/companies/c1/delegates/dm", {position: "promoter"});
    await put("organizations/o1/companies/c1/delegates/sm", {position: "supervisor"});
    await put("organizations/o2/companies/c1/delegates/sm", {position: "مشرف"});
    await put("organizations/o2/companies/c1/delegates/sup", {position: "supervisor"});
    await put("organizations/o2/companies/c2/delegates/sup2", {position: "supervisor"});
    await put("organizations/o1/companies/c1/delegates/ds", {position: "promoter"});
    await put("organizations/o1/companies/c1/delegates/ss", {position: "Supervisor"});
    await put("organizations/o1/companies/c1/delegates/peer", {position: "promoter"});
  });
});
after(async () => env && env.cleanup());

const as = (uid, extra) => env.authenticatedContext(uid, token(uid, extra)).firestore();
const delegatesOf = (db, org, co) => collection(db, `organizations/${org}/companies/${co}/delegates`);
const supervisors = (db, org, co) => query(
  delegatesOf(db, org, co),
  where("position", "in", ["supervisor", "Supervisor", "مشرف"]),
);

describe("TAS-55 plain delegate (promoter)", () => {
  test("reads its own document", () =>
    assertSucceeds(getDoc(doc(as("ds"), "organizations/o1/companies/c1/delegates/ds"))));
  test("cannot read a coworker", () =>
    assertDeniedByRule(getDoc(doc(as("ds"), "organizations/o1/companies/c1/delegates/peer"))));
  test("cannot read the supervisor's document", () =>
    assertDeniedByRule(getDoc(doc(as("ds"), "organizations/o1/companies/c1/delegates/ss"))));
  test("cannot list the company's supervisors", () =>
    assertDeniedByRule(getDocs(supervisors(as("ds"), "o1", "c1"))));
  test("cannot list the company's delegates", () =>
    assertDeniedByRule(getDocs(delegatesOf(as("ds"), "o1", "c1"))));
  test("multi-chain promoter cannot list supervisors in the second chain", () =>
    assertDeniedByRule(getDocs(supervisors(as("dm", MULTI), "o2", "c1"))));
});

describe("TAS-55 supervisor", () => {
  test("lists every delegate of its company", () =>
    assertSucceeds(getDocs(delegatesOf(as("ss"), "o1", "c1"))));
  test("reads a delegate's full document", () =>
    assertSucceeds(getDoc(doc(as("ss"), "organizations/o1/companies/c1/delegates/peer"))));
  test("another chain it is not in stays denied", () =>
    assertDeniedByRule(getDocs(supervisors(as("ss"), "o2", "c1"))));
});

describe("TAS-242 multi-chain supervisor", () => {
  test("lists supervisors in the second chain's company it belongs to", () =>
    assertSucceeds(getDocs(supervisors(as("sm", MULTI), "o2", "c1"))));
  test("reads a delegate doc there", () =>
    assertSucceeds(getDoc(doc(as("sm", MULTI), "organizations/o2/companies/c1/delegates/dm"))));
  test("org x company pair it is not in stays denied", () =>
    assertDeniedByRule(getDocs(supervisors(as("sm", MULTI), "o2", "c2"))));
  test("first chain still works", () =>
    assertSucceeds(getDocs(supervisors(as("sm", MULTI), "o1", "c1"))));
});
