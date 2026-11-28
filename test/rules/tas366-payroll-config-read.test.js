/**
 * TAS-366: the delegate's «مرتبي» screen reads
 *  - company_payroll_configs/{companyId} of his own company only (claims
 *    companyId / companyIds), read only;
 *  - his own user_wallets doc only;
 *  - his own attendance, approved leaves and penalties (the screen's queries).
 * Fake data only.
 *
 * npm run test:rules:tas366-payroll
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, Timestamp,
} = require("firebase/firestore");

let env;
const D1 = {role: "delegate", delegateId: "d1", orgId: "o1", companyId: "c1"};
// Supervisor delegate in two companies (TAS-242 multi-company claims).
const SUP = {role: "delegate", delegateId: "sup", delegateIds: ["sup"], orgId: "o1", orgIds: ["o1", "o2"], companyId: "c1", companyIds: ["c1", "c2"]};
const OTP_PENDING = {...D1, otp_required: true, otp_verified: false};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas366-payroll",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/hr"), {role: "hr", organizationUID: "o1", companyUID: "c1", fake: true});
    await setDoc(doc(db, "company_payroll_configs/c1"), {calculationMode: "monthly_with_deductions", defaultMonthlyBaseSalary: 4000});
    await setDoc(doc(db, "company_payroll_configs/c2"), {calculationMode: "hourly_rate"});
    await setDoc(doc(db, "company_payroll_configs/c3"), {calculationMode: "hourly_rate"});
    await setDoc(doc(db, "user_wallets/d1"), {companyUID: "c1", baseSalary: 3000});
    await setDoc(doc(db, "user_wallets/d2"), {companyUID: "c1", baseSalary: 9000});
    const t = Timestamp.fromDate(new Date("2026-11-03T08:00:00"));
    await setDoc(doc(db, "attendance_logs/a1"), {delegateId: "d1", userId: "d1", companyId: "c1", organizationId: "o1", type: "check_in", timestamp: t});
    await setDoc(doc(db, "attendance_logs/a2"), {delegateId: "d2", userId: "d2", companyId: "c1", organizationId: "o1", type: "check_in", timestamp: t});
    await setDoc(doc(db, "leave_requests/l1"), {delegateUid: "d1", companyUID: "c1", organizationUID: "o1", status: "approved", type: "annual", startDate: t});
    await setDoc(doc(db, "penalties/p1"), {targetDelegateId: "d1", companyId: "c1", organizationId: "o1", status: "ISSUED", fineAmount: 50, createdAt: t});
  });
});

after(async () => env && env.cleanup());

const db = (uid, token) => env.authenticatedContext(uid, token).firestore();

describe("company_payroll_configs: delegate reads his company only (TAS-366)", () => {
  test("delegate reads his company's config", async () => {
    await assertSucceeds(getDoc(doc(db("d1", D1), "company_payroll_configs/c1")));
  });
  test("supervisor delegate reads each of his companies", async () => {
    await assertSucceeds(getDoc(doc(db("sup", SUP), "company_payroll_configs/c1")));
    await assertSucceeds(getDoc(doc(db("sup", SUP), "company_payroll_configs/c2")));
  });
  test("delegate cannot read another company's config", async () => {
    await assertDeniedByRule(getDoc(doc(db("d1", D1), "company_payroll_configs/c2")));
    await assertDeniedByRule(getDoc(doc(db("sup", SUP), "company_payroll_configs/c3")));
  });
  test("delegate cannot list configs", async () => {
    await assertDeniedByRule(getDocs(collection(db("d1", D1), "company_payroll_configs")));
  });
  test("delegate with a pending OTP cannot read", async () => {
    await assertDeniedByRule(getDoc(doc(db("d1", OTP_PENDING), "company_payroll_configs/c1")));
  });
  test("delegate cannot write his company's config", async () => {
    const d = db("d1", D1);
    await assertDeniedByRule(setDoc(doc(d, "company_payroll_configs/c1"), {defaultMonthlyBaseSalary: 99999}));
    await assertDeniedByRule(updateDoc(doc(d, "company_payroll_configs/c1"), {defaultMonthlyBaseSalary: 99999}));
    await assertDeniedByRule(deleteDoc(doc(d, "company_payroll_configs/c1")));
  });
  test("HR still reads and writes his company's config", async () => {
    await assertSucceeds(getDoc(doc(db("hr"), "company_payroll_configs/c1")));
    await assertSucceeds(updateDoc(doc(db("hr"), "company_payroll_configs/c1"), {defaultMonthlyBaseSalary: 4100}));
  });
});

describe("«مرتبي» screen reads (TAS-366)", () => {
  test("delegate reads his own wallet only, read only", async () => {
    await assertSucceeds(getDoc(doc(db("d1", D1), "user_wallets/d1")));
    await assertDeniedByRule(getDoc(doc(db("d1", D1), "user_wallets/d2")));
    await assertDeniedByRule(updateDoc(doc(db("d1", D1), "user_wallets/d1"), {baseSalary: 99999}));
  });
  test("delegate's own attendance query (delegateId + timestamp)", async () => {
    const d = db("d1", D1);
    await assertSucceeds(getDocs(query(collection(d, "attendance_logs"),
      where("delegateId", "==", "d1"),
      where("timestamp", ">=", Timestamp.fromDate(new Date("2026-10-01T00:00:00"))))));
    await assertDeniedByRule(getDocs(query(collection(d, "attendance_logs"), where("delegateId", "==", "d2"))));
  });
  test("delegate's own leaves query (companyUID + delegateUid)", async () => {
    const d = db("d1", D1);
    await assertSucceeds(getDocs(query(collection(d, "leave_requests"),
      where("companyUID", "==", "c1"), where("delegateUid", "==", "d1"))));
  });
  test("delegate's own penalties query (targetDelegateId)", async () => {
    const d = db("d1", D1);
    await assertSucceeds(getDocs(query(collection(d, "penalties"), where("targetDelegateId", "==", "d1"))));
    await assertDeniedByRule(getDocs(query(collection(d, "penalties"), where("targetDelegateId", "==", "d2"))));
  });
});
