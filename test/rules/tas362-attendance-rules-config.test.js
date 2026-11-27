/**
 * TAS-362: system_config/attendance_rules (start date of the «forgotten
 * session = zero» rule). Signed-in staff and delegates read it; only a super
 * admin writes it. Fake data only.
 *
 * npm run test:rules:tas362-attendance-config
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, getDoc, setDoc, Timestamp} = require("firebase/firestore");

const PATH = "system_config/attendance_rules";
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas362-config",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/sa"), {role: "super_admin", fake: true});
    await setDoc(doc(db, "users/hr"), {role: "hr", organizationUID: "o1", companyUID: "c1", fake: true});
    await setDoc(doc(db, PATH), {missingCheckOutRuleFrom: Timestamp.fromDate(new Date("2026-11-28"))});
  });
});

after(async () => env && env.cleanup());

const db = (uid, token) => env.authenticatedContext(uid, token).firestore();
const write = (d) => setDoc(doc(d, PATH), {missingCheckOutRuleFrom: Timestamp.now()});

describe("system_config/attendance_rules (TAS-362)", () => {
  test("HR and a delegate token can read it", async () => {
    await assertSucceeds(getDoc(doc(db("hr"), PATH)));
    await assertSucceeds(getDoc(doc(db("d1", {role: "delegate", delegateId: "d1", orgId: "o1"}), PATH)));
  });
  test("signed out cannot read", async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), PATH)));
  });
  test("only a super admin writes it", async () => {
    await assertSucceeds(write(db("sa")));
    await assertFails(write(db("hr")));
    await assertFails(write(db("d1", {role: "delegate", delegateId: "d1", orgId: "o1"})));
  });
});
