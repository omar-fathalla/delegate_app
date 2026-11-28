/**
 * TAS-370: how far back a delegate may file a leave (user decision
 * 2026-11-27): sick / emergency / excused absence 7 days, hourly excuses
 * 30 days, annual / unpaid from today. endDate never before startDate.
 * Staff (HR) still record any date. Fake data only.
 *
 * npm run test:rules:tas370-leave
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, serverTimestamp, Timestamp} = require("firebase/firestore");

const ORG = "seed-fake-tas370-org";
const CO = "seed-fake-tas370-co";
const DAY = 86400000;
let env;
let n = 0;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas370-leave",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/hr-1"), {role: "hr", organizationUID: ORG, companyUID: CO, fake: true});
    await setDoc(doc(db, `organizations/${ORG}`), {name: ORG, fake: true});
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}`), {name: CO, organizationUID: ORG, fake: true});
  });
});

after(async () => env && env.cleanup());

const delegate = () => env.authenticatedContext("del-1", {
  role: "delegate", delegateId: "del-1", orgId: ORG, companyId: CO,
}).firestore();
const hr = () => env.authenticatedContext("hr-1").firestore();

// Local midnight, `daysAgo` days back, as the app's picker sends it.
const dayStart = (daysAgo) => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return Timestamp.fromMillis(d.getTime() - daysAgo * DAY);
};

const leave = (over) => ({
  id: "x", delegateUid: "del-1", delegateName: "Fake", delegatePhone: "01000000000",
  companyUID: CO, organizationUID: ORG, type: "annual", isHourly: false, hoursCount: null,
  startDate: dayStart(0), endDate: dayStart(0), daysCount: 1,
  reason: "r", attachmentUrl: null, createdAt: serverTimestamp(), status: "pending",
  resolvedAt: null, resolvedBy: null, resolvedByName: null, rejectReason: null, ...over,
});
const file = (db, data) => setDoc(doc(db, `leave_requests/l-${++n}`), data);

describe("TAS-370: leave backdate limit (delegate)", () => {
  test("annual from today and in the future is allowed", async () => {
    await assertSucceeds(file(delegate(), leave()));
    await assertSucceeds(file(delegate(), leave({startDate: dayStart(-3), endDate: dayStart(-5)})));
  });
  test("annual and unpaid before today are denied", async () => {
    await assertDeniedByRule(file(delegate(), leave({startDate: dayStart(2), endDate: dayStart(1)})));
    await assertDeniedByRule(file(delegate(), leave({type: "unpaid", startDate: dayStart(3), endDate: dayStart(3)})));
  });
  test("sick, emergency and absence up to 7 days back are allowed", async () => {
    for (const type of ["sick", "emergency", "absence"]) {
      await assertSucceeds(file(delegate(), leave({type, startDate: dayStart(7), endDate: dayStart(6)})));
    }
  });
  test("sick, emergency and absence older than 7 days are denied", async () => {
    for (const type of ["sick", "emergency", "absence"]) {
      await assertDeniedByRule(file(delegate(), leave({type, startDate: dayStart(9), endDate: dayStart(8)})));
    }
  });
  test("an old app's 2024 date is denied", async () => {
    await assertDeniedByRule(file(delegate(), leave({type: "sick",
      startDate: Timestamp.fromDate(new Date("2024-03-01T00:00:00")),
      endDate: Timestamp.fromDate(new Date("2024-03-02T00:00:00"))})));
  });
  test("hourly excuses keep 30 days", async () => {
    const hourly = {type: "delay", isHourly: true, hoursCount: 2, daysCount: 0};
    await assertSucceeds(file(delegate(), leave({...hourly, startDate: dayStart(30), endDate: dayStart(30)})));
    await assertDeniedByRule(file(delegate(), leave({...hourly, startDate: dayStart(33), endDate: dayStart(33)})));
  });
  test("endDate before startDate is denied", async () => {
    await assertDeniedByRule(file(delegate(), leave({startDate: dayStart(-5), endDate: dayStart(-2)})));
  });
  test("missing dates are denied", async () => {
    const d = leave();
    delete d.startDate;
    await assertDeniedByRule(file(delegate(), d));
  });
});

describe("TAS-370: HR is not limited", () => {
  test("HR records an approved leave months back", async () => {
    await assertSucceeds(file(hr(), leave({
      type: "sick", startDate: dayStart(90), endDate: dayStart(88), status: "approved",
      resolvedAt: serverTimestamp(), resolvedBy: "hr-1", resolvedByName: "HR",
    })));
  });
});
