/**
 * TAS-50 (user decision 2026-11-24): penalty_rules is one fixed catalog for
 * every company. Every signed-in user reads it; only a super-admin creates,
 * edits or deletes an entry. Before, any company staff (isStaffWriter) could
 * change the fines of every other company. Fake data only.
 *
 * npm run test:rules:tas50
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection} = require("firebase/firestore");

const ORG = "seed-fake-tas50-org";
const CO = "seed-fake-tas50-co";

const staff = {
  "sa": {role: "super-admin"},
  "tech": {role: "technical_support"},
  "orgadmin": {role: "organization-admin", organizationUID: ORG},
  "admin": {role: "company-admin", organizationUID: ORG, companyUID: CO},
  "hr": {role: "hr", organizationUID: ORG, companyUID: CO},
  "acc": {role: "accountant", organizationUID: ORG, companyUID: CO},
  "mk": {role: "marketing", organizationUID: ORG},
};

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();
const asDelegate = () => env.authenticatedContext("del-1", {
  role: "delegate", orgId: ORG, companyId: CO, delegateId: "del-1", otp_verified: true,
}).firestore();
const rule = {title: "تأخير", amount: 50, multiplier: 2, fake: true};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas50",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    await setDoc(doc(db, "penalty_rules/r-1"), rule);
  });
});

after(async () => {
  await env?.cleanup();
});

describe("penalty_rules catalog", () => {
  test("every signed-in user reads the catalog", async () => {
    for (const uid of Object.keys(staff)) {
      await assertSucceeds(getDocs(collection(as(uid), "penalty_rules")));
    }
    await assertSucceeds(getDoc(doc(asDelegate(), "penalty_rules/r-1")));
  });

  test("super-admin creates, edits and deletes an entry", async () => {
    const db = as("sa");
    await assertSucceeds(setDoc(doc(db, "penalty_rules/r-new"), rule));
    await assertSucceeds(updateDoc(doc(db, "penalty_rules/r-new"), {amount: 75}));
    await assertSucceeds(deleteDoc(doc(db, "penalty_rules/r-new")));
  });

  for (const uid of ["tech", "orgadmin", "admin", "hr", "acc", "mk"]) {
    test(`${staff[uid].role} cannot change the catalog`, async () => {
      const db = as(uid);
      await assertDeniedByRule(setDoc(doc(db, `penalty_rules/r-${uid}`), rule));
      await assertDeniedByRule(updateDoc(doc(db, "penalty_rules/r-1"), {amount: 1}));
      await assertDeniedByRule(deleteDoc(doc(db, "penalty_rules/r-1")));
    });
  }

  test("a delegate cannot change the catalog", async () => {
    const db = asDelegate();
    await assertDeniedByRule(setDoc(doc(db, "penalty_rules/r-del"), rule));
    await assertDeniedByRule(updateDoc(doc(db, "penalty_rules/r-1"), {amount: 1}));
  });
});
