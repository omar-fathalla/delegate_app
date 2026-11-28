/**
 * TAS-365: the rules were not opened for delegates. A delegate still cannot
 * update its penalty directly (acknowledge / dispute go through
 * respondToPenalty), it reads the notification the server wrote for it, and
 * a staff status change with the new marker fields still passes.
 * Fake data only.
 *
 * npm run test:rules:tas365-penalty-rules
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, getDoc, setDoc, updateDoc, serverTimestamp} = require("firebase/firestore");

let env;
const penalty = {
  penaltyId: "p1", status: "ISSUED", targetDelegateId: "d1", companyId: "c1", companyUID: "c1",
  organizationId: "o1", organizationUID: "o1", title: "تأخير", fineAmount: 100,
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas365-rules",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "penalties/p1"), penalty);
    await setDoc(doc(db, "notifications/penalty_p1_del_issued"), {
      delegateUid: "d1", organizationUID: "o1", organizationId: "o1", companyUID: "c1", companyId: "c1",
      title: "عليك جزاء جديد", body: "x", type: "penalty", penaltyId: "p1", isRead: false, createdBy: "system",
    });
    await setDoc(doc(db, "users/hr1"), {role: "hr", companyUID: "c1", organizationUID: "o1"});
  });
});

after(async () => env && env.cleanup());

const del = (id) => env.authenticatedContext(id,
  {role: "delegate", delegateId: id, orgId: "o1", companyId: "c1"}).firestore();

describe("TAS-365: penalty dispute stays server-side", () => {
  test("the delegate cannot dispute by writing the penalty", async () => {
    await assertFails(updateDoc(doc(del("d1"), "penalties/p1"), {status: "DISPUTED", disputeReason: "غلط"}));
  });
  test("the delegate cannot acknowledge by writing the penalty", async () => {
    await assertFails(updateDoc(doc(del("d1"), "penalties/p1"), {status: "ACKNOWLEDGED"}));
  });
  test("the delegate reads the server's penalty notification", async () => {
    await assertSucceeds(getDoc(doc(del("d1"), "notifications/penalty_p1_del_issued")));
  });
  test("a colleague cannot read it", async () => {
    await assertFails(getDoc(doc(del("d2"), "notifications/penalty_p1_del_issued")));
  });
  test("HR in the company still changes the status with the server marker", async () => {
    const hr = env.authenticatedContext("hr1", {role: "hr", companyId: "c1", orgId: "o1"}).firestore();
    await assertSucceeds(updateDoc(doc(hr, "penalties/p1"), {
      status: "DEDUCTED", updatedAt: serverTimestamp(), notifyByServerAt: serverTimestamp(),
    }));
  });
});
