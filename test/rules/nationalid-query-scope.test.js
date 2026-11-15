/**
 * TA-34: company staff must scope duplicate / nationalId list queries by companyUID.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {collection, query, where, getDocs} = require("firebase/firestore");

const PROJECT_ID = "demo-nationalid-scope";

describe("nationalId query company scope (TA-34)", () => {
  let env;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
    });
  });

  after(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sup").set({
        role: "supervisor",
        organizationUID: "o1",
        companyUID: "c1",
      });
      await db.doc("delegate_requests/r-c1").set({
        organizationUID: "o1",
        companyUID: "c1",
        nationalId: "29101010100011",
        status: "pending",
      });
      await db.doc("delegate_requests/r-c2").set({
        organizationUID: "o1",
        companyUID: "c2",
        nationalId: "29101010100011",
        status: "pending",
      });
    });
  });

  const as = (uid) =>
    env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  test("supervisor cannot list delegate_requests by nationalId without companyUID", async () => {
    const sup = as("sup");
    await assertFails(
      getDocs(query(collection(sup, "delegate_requests"), where("nationalId", "==", "29101010100011"))),
    );
  });

  test("supervisor may list when companyUID is in the query", async () => {
    const sup = as("sup");
    const snap = await assertSucceeds(
      getDocs(query(
        collection(sup, "delegate_requests"),
        where("companyUID", "==", "c1"),
        where("nationalId", "==", "29101010100011"),
      )),
    );
    if (snap.size !== 1) throw new Error(`expected 1 doc, got ${snap.size}`);
  });
});