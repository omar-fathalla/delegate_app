/**
 * Global penalties read scope for HR, accountant, marketing (Mohamed 2025-11-15).
 * npm run test:rules:security
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");

describe("penalties company scope by role", () => {
  let env;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-suspend-login-penalties",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });

  after(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const staff = {
        hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
        accountant: {role: "accountant", organizationUID: "o1", companyUID: "c1"},
        marketing: {role: "marketing", organizationUID: "o1", companyUID: "c1"},
        marketingC2: {role: "marketing", organizationUID: "o1", companyUID: "c2"},
        supervisor: {role: "company-admin", organizationUID: "o1", companyUID: "c1"},
      };
      for (const [id, data] of Object.entries(staff)) {
        await db.doc(`users/${id}`).set(data);
      }
      await db.doc("penalties/p-c1").set({
        companyId: "c1",
        companyUID: "c1",
        organizationId: "o1",
        organizationUID: "o1",
        targetDelegateId: "del-1",
      });
      await db.doc("penalties/p-c2").set({
        companyId: "c2",
        companyUID: "c2",
        organizationId: "o1",
        organizationUID: "o1",
        targetDelegateId: "del-2",
      });
    });
  });

  function dbFor(uid) {
    return env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();
  }

  for (const role of ["hr", "accountant", "marketing", "supervisor"]) {
    test(`${role} reads own-company penalties list`, async () => {
      const db = dbFor(role);
      await assertSucceeds(db.collection("penalties").where("companyId", "==", "c1").get());
      await assertFails(db.collection("penalties").where("companyId", "==", "c2").get());
    });

    test(`${role} cannot get another company's penalty doc`, async () => {
      const db = dbFor(role);
      await assertSucceeds(db.doc("penalties/p-c1").get());
      await assertFails(db.doc("penalties/p-c2").get());
    });
  }

  test("marketing with companyUID cannot list whole org penalties", async () => {
    const db = dbFor("marketing");
    await assertFails(db.collection("penalties").where("organizationId", "==", "o1").get());
  });

  test("marketing c2 is isolated from c1 penalties", async () => {
    const db = dbFor("marketingC2");
    await assertSucceeds(db.doc("penalties/p-c2").get());
    await assertFails(db.doc("penalties/p-c1").get());
  });
});