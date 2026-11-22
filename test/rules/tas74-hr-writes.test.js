/**
 * TAS-74: HR writes from the HR screens.
 * - Payroll (_saveDelegateSalary): HR / company supervisor create or update
 *   only the salary fields of a wallet in their own company; never balance,
 *   never another company's wallet.
 * - Pending delegate placeholder stays denied for HR (company-scoping-gaps
 *   keeps that deny); the app hides «إضافة مندوب» for HR instead.
 * Fake data only.
 *
 * npm run test:rules:tas74-hr
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, setDoc} = require("firebase/firestore");

const ORG = "seed-fake-tas74-org";
const CO_A = "seed-fake-tas74-co-a";
const CO_B = "seed-fake-tas74-co-b";

const staff = {
  "hr-a": {role: "hr", organizationUID: ORG, companyUID: CO_A},
  "sup-a": {role: "supervisor", organizationUID: ORG, companyUID: CO_A},
  "acc-a": {role: "accountant", organizationUID: ORG, companyUID: CO_A},
  "hr-nocompany": {role: "hr", organizationUID: ORG},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas74-hr",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    await setDoc(doc(db, "user_wallets/del-a-old"), {companyUID: CO_A, balance: 100, baseSalary: 3000, fake: true});
    await setDoc(doc(db, "user_wallets/del-b-old"), {companyUID: CO_B, balance: 100, baseSalary: 3000, fake: true});
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();

// Mirrors hr_monthly_payroll_screen _saveDelegateSalary (set, merge).
const salary = (co) => ({
  monthlyAllocation: 4000, baseSalary: 4000, dailyShiftHours: 8, customHourlyRate: null,
  payrollCalculationMode: "monthly", companyUID: co, companyName: "fake", userName: "Fake",
  userPhone: "01000000000", updatedAt: new Date("2026-11-22T10:00:00Z"), updatedBy: "HR",
});
const save = (uid, walletId, data) => setDoc(doc(as(uid), `user_wallets/${walletId}`), data, {merge: true});

describe("payroll wallet writes (HR / supervisor)", () => {
  for (const uid of ["hr-a", "sup-a"]) {
    test(`${uid} saves salary on an existing wallet of its company`, async () => {
      await assertSucceeds(save(uid, "del-a-old", salary(CO_A)));
    });

    test(`${uid} creates the wallet of a delegate with no wallet yet`, async () => {
      await assertSucceeds(save(uid, `del-a-new-${uid}`, salary(CO_A)));
    });

    test(`${uid} cannot change the balance`, async () => {
      await assertFails(save(uid, "del-a-old", {...salary(CO_A), balance: 999999}));
    });

    test(`${uid} cannot touch another company's wallet`, async () => {
      await assertFails(save(uid, "del-b-old", salary(CO_A)));
      await assertFails(save(uid, "del-b-old", salary(CO_B)));
    });

    test(`${uid} cannot create a wallet for another company`, async () => {
      await assertFails(save(uid, `del-b-new-${uid}`, salary(CO_B)));
    });
  }

  test("HR without a company cannot write wallets", async () => {
    await assertFails(save("hr-nocompany", "del-a-old", salary(CO_A)));
  });

  test("accountant keeps its existing write", async () => {
    await assertSucceeds(save("acc-a", "del-a-old", salary(CO_A)));
  });
});
