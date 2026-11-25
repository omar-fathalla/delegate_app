/**
 * TAS-333: a delegate's check-in must name a branch of one of its own chains.
 *
 * Two chains have a branch at the same place. The delegate is a member of
 * o-own only (or o-own + o-second when multi-chain). A check-in whose
 * branchOrganizationUID is a chain it is not a member of is denied; old
 * logs without the field keep working. Fake data only.
 *
 * npm run test:rules:tas333
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, serverTimestamp} = require("firebase/firestore");

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas333",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
});
after(async () => env && env.cleanup());

const delegate = (extra = {}) => env.authenticatedContext("del-1", {
  role: "delegate", orgId: "o-own", companyId: "c-own", delegateId: "del-1", ...extra,
}).firestore();

const checkIn = (over) => ({
  delegateId: "del-1", userId: "del-1", companyId: "c-own", organizationId: "o-own",
  timestamp: serverTimestamp(), type: "check_in", location: {latitude: 30.1001, longitude: 31.2001},
  deviceInfo: "fake", branchName: "Fake Branch QR", branchId: "br-own",
  branchOrganizationUID: "o-own", ...over,
});

describe("TAS-333 check-in branch chain", () => {
  test("own chain branch is allowed", () =>
    assertSucceeds(setDoc(doc(delegate(), "attendance_logs/own"), checkIn())));

  test("branch of a chain the delegate is not in is denied", () =>
    assertDeniedByRule(setDoc(doc(delegate(), "attendance_logs/foreign"), checkIn({
      branchName: "Fake Branch Alpha", branchId: "br-alpha", branchOrganizationUID: "o-other",
    }))));

  test("empty branchOrganizationUID is denied", () =>
    assertDeniedByRule(setDoc(doc(delegate(), "attendance_logs/empty"),
      checkIn({branchOrganizationUID: ""}))));

  test("legacy log without branchOrganizationUID still passes", () => {
    const legacy = checkIn();
    delete legacy.branchOrganizationUID;
    delete legacy.branchId;
    return assertSucceeds(setDoc(doc(delegate(), "attendance_logs/legacy"), legacy));
  });

  test("multi-chain delegate: branch of its second chain is a member chain", () =>
    assertSucceeds(setDoc(doc(delegate({orgIds: ["o-own", "o-second"], companyIds: ["c-own", "c-2"]}),
      "attendance_logs/second"), checkIn({branchOrganizationUID: "o-second", branchId: "br-2"}))));

  test("multi-chain delegate: still denied for a chain outside its claims", () =>
    assertDeniedByRule(setDoc(doc(delegate({orgIds: ["o-own", "o-second"], companyIds: ["c-own", "c-2"]}),
      "attendance_logs/outside"), checkIn({branchOrganizationUID: "o-other"}))));
});
