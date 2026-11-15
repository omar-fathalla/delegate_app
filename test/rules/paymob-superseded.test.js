/**
 * Paymob superseded payment collections (read: SA/tech only).
 * Emulator: npx firebase emulators:exec --only firestore --project demo-paymob-super \
 *   "node --test test/rules/paymob-superseded.test.js"
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc} = require("firebase/firestore");

const PROJECT_ID = "demo-paymob-super";
const SUPER_DOC = {
  requestId: "ren1",
  attemptId: "1700000000001_oldabcd12",
  needs_refund: true,
  amountCents: 41667,
  companyUID: "c1",
  organizationUID: "o1",
};

describe("paymob superseded collections", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sa").set({role: "super-admin"});
      await db.doc("users/ts").set({role: "technical_support"});
      await db.doc("users/sup").set({role: "supervisor", companyUID: "c1", organizationUID: "o1"});
      await db.doc("paymob_superseded_payments/82001").set(SUPER_DOC);
      await db.doc("admin_alerts/82001").set({type: "paymob_superseded_payment", ...SUPER_DOC});
    });
  });

  test("super-admin and technical support can read paymob_superseded_payments", async () => {
    await assertSucceeds(getDoc(doc(as("sa"), "paymob_superseded_payments/82001")));
    await assertSucceeds(getDoc(doc(as("ts"), "paymob_superseded_payments/82001")));
  });

  test("company staff cannot read paymob_superseded_payments", async () => {
    await assertFails(getDoc(doc(as("sup"), "paymob_superseded_payments/82001")));
  });

  test("super-admin and technical support can read admin_alerts", async () => {
    await assertSucceeds(getDoc(doc(as("sa"), "admin_alerts/82001")));
    await assertSucceeds(getDoc(doc(as("ts"), "admin_alerts/82001")));
  });

  test("supervisor cannot read admin_alerts", async () => {
    await assertFails(getDoc(doc(as("sup"), "admin_alerts/82001")));
  });

  test("clients cannot write paymob_superseded_payments", async () => {
    await assertFails(as("sa").doc("paymob_superseded_payments/x").set({needs_refund: true}));
  });
});