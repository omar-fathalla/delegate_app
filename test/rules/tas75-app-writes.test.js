/**
 * TAS-75: app paths the new rules used to deny.
 * - system_config/session_control: every signed-in app reads it; only a
 *   super admin writes the emergency reset.
 * - The supervisor's existing-public-id lookup on delegates is company
 *   scoped (companyUID + nationalId) and allowed.
 * Fake data only.
 *
 * npm run test:rules:tas75
 */
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {
  doc, setDoc, getDoc, getDocs, deleteDoc, collectionGroup, query, where, limit,
} = require("firebase/firestore");

const ORG = "seed-fake-tas75-org";
const CO_A = "seed-fake-tas75-co-a";
const CO_B = "seed-fake-tas75-co-b";

const users = {
  "sa-1": {role: "super-admin"},
  "tech-1": {role: "technical_support"},
  "hr-a": {role: "hr", organizationUID: ORG, companyUID: CO_A},
  "sup-a": {role: "supervisor", organizationUID: ORG, companyUID: CO_A},
  "del-x": {role: "delegate", organizationUID: ORG, companyUID: CO_A, uid: "del-x"},
  "del-y": {role: "delegate", organizationUID: ORG, companyUID: CO_B, uid: "del-y"},
  "hr-z": {role: "hr", organizationUID: ORG, companyUID: CO_B},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas75",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    await setDoc(doc(db, "system_config/session_control"), {reason: "fake", fake: true});
    for (const co of [CO_A, CO_B]) {
      await setDoc(doc(db, `organizations/${ORG}/companies/${co}/delegates/d-${co}`), {
        companyUID: co, organizationUID: ORG, nationalId: "29001010000000",
        delegatePublicId: `DEL-${co}`, status: "active", fake: true,
      });
    }
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const delegateDb = () => env.authenticatedContext("del-x", {
  role: "delegate", delegateId: "del-x", delegateIds: ["del-x"], orgId: ORG, companyId: CO_A,
}).firestore();

describe("system_config/session_control", () => {
  test("a delegate reads it at start", async () => {
    await assertSucceeds(getDoc(doc(delegateDb(), "system_config/session_control")));
  });

  test("staff read it", async () => {
    await assertSucceeds(getDoc(doc(as("hr-a"), "system_config/session_control")));
  });

  test("super admin writes the emergency reset", async () => {
    await assertSucceeds(setDoc(doc(as("sa-1"), "system_config/session_control"), {
      globalForceLogoutBefore: new Date("2026-11-22T10:00:00Z"), reason: "fake", updatedBy: "sa-1",
    }, {merge: true}));
  });

  for (const uid of ["tech-1", "hr-a", "sup-a"]) {
    test(`${uid} cannot write it`, async () => {
      await assertFails(setDoc(doc(as(uid), "system_config/session_control"), {reason: "x"}, {merge: true}));
    });
  }

  test("a delegate cannot write it", async () => {
    await assertFails(setDoc(doc(delegateDb(), "system_config/session_control"), {reason: "x"}, {merge: true}));
  });
});

// Technical support deleting a users doc stays denied (users-p0 and
// adversarial keep that deny); the orphan users doc is removed server side
// instead (follow-up sub-issue of TAS-75).
describe("technical support cannot delete users docs", () => {
  test("denied, even for a delegate", async () => {
    await assertFails(deleteDoc(doc(as("tech-1"), "users/del-x")));
  });
});

describe("existing public id lookup (submitSubscriptionRequest)", () => {
  test("supervisor finds a same-company record by companyUID + nationalId", async () => {
    const snap = await assertSucceeds(getDocs(query(
      collectionGroup(as("sup-a"), "delegates"),
      where("companyUID", "==", CO_A),
      where("nationalId", "==", "29001010000000"),
      limit(1),
    )));
    assert.deepStrictEqual(snap.docs.map((d) => d.data().companyUID), [CO_A]);
  });
});
