/**
 * TAS-371: the delegate reads the decision notification the server wrote
 * for it (createdBy "system"), never a colleague's. Fake data only.
 *
 * npm run test:rules:tas371-read
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

let env;
const n = (delegateUid) => ({
  delegateUid, organizationUID: "o1", organizationId: "o1", companyUID: "c1", companyId: "c1",
  title: "تمت الموافقة على طلب الإجازة / العذر", body: "x", type: "leave_approved",
  requestId: "l1", isRead: false, createdBy: "system", senderName: "HR",
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas371-read",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "notifications/leave_l1_approved"), n("d1"));
  });
});

after(async () => env && env.cleanup());

const del = (id) => env.authenticatedContext(id, {role: "delegate", delegateId: id, orgId: "o1", companyId: "c1"}).firestore();

describe("TAS-371: server decision notifications", () => {
  test("the delegate reads its own", async () => {
    await assertSucceeds(getDoc(doc(del("d1"), "notifications/leave_l1_approved")));
  });
  test("a colleague cannot", async () => {
    await assertFails(getDoc(doc(del("d2"), "notifications/leave_l1_approved")));
  });
});
