/**
 * TAS-368: a delegate marks a shared task («الكل») done for itself only, in
 * tasks/{taskId}/completions/{uid}. Never a colleague's doc, never cancelled,
 * proof first when the task needs one. Fake data only.
 *
 * npm run test:rules:tas368-completions
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {doc, setDoc, getDoc, getDocs, collection, updateDoc, serverTimestamp} = require("firebase/firestore");

const ORG = "seed-fake-tas368-org";
const CO = "seed-fake-tas368-co";
const task = (id) => `organizations/${ORG}/tasks/${id}`;
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas368",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/hr"), {role: "hr", organizationUID: ORG, companyUID: CO, fake: true});
    const base = {title: "t", status: "pending", companyId: CO, createdBy: "hr", fake: true};
    await setDoc(doc(db, task("shared")), {...base, assignedTo: "all"});
    await setDoc(doc(db, task("shared-proof")), {...base, assignedTo: "all", proofRequired: true});
    await setDoc(doc(db, task("cancelled")), {...base, assignedTo: "all", status: "cancelled"});
    await setDoc(doc(db, task("own")), {...base, assignedTo: "del-1"});
  });
});

after(async () => env && env.cleanup());

const asDel = (uid) => env.authenticatedContext(uid, {role: "delegate", orgId: ORG, companyId: CO, delegateId: uid})
  .firestore();
const done = (extra = {}) => ({status: "completed", completedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra});
const comp = (db, t, uid) => doc(db, `${task(t)}/completions/${uid}`);

describe("task completions (TAS-368)", () => {
  test("a delegate marks a shared task done for itself", async () => {
    await assertSucceeds(setDoc(comp(asDel("del-1"), "shared", "del-1"), done({notes: "تم"})));
    await assertSucceeds(getDoc(comp(asDel("del-1"), "shared", "del-1")));
  });
  test("never a colleague's completion, and cannot read it", async () => {
    await assertFails(setDoc(comp(asDel("del-1"), "shared", "del-2"), done()));
    await assertFails(getDoc(comp(asDel("del-2"), "shared", "del-1")));
  });
  test("no cancelled, no extra fields, server times only", async () => {
    const db = asDel("del-3");
    await assertFails(setDoc(comp(db, "shared", "del-3"), {status: "cancelled", updatedAt: serverTimestamp()}));
    await assertFails(setDoc(comp(db, "shared", "del-3"), done({completedBy: "someone"})));
    await assertFails(setDoc(comp(db, "shared", "del-3"), {status: "completed", completedAt: new Date(), updatedAt: serverTimestamp()}));
    await assertSucceeds(setDoc(comp(db, "shared", "del-3"), {status: "inProgress", updatedAt: serverTimestamp()}));
  });
  test("cancelled task and an individual task: no completions", async () => {
    await assertFails(setDoc(comp(asDel("del-1"), "cancelled", "del-1"), done()));
    await assertFails(setDoc(comp(asDel("del-1"), "own", "del-1"), done()));
  });
  test("proofRequired: completed only after the delegate's own proof", async () => {
    const db = asDel("del-4");
    await assertFails(setDoc(comp(db, "shared-proof", "del-4"), done()));
    await assertSucceeds(setDoc(comp(db, "shared-proof", "del-4"), {status: "inProgress", updatedAt: serverTimestamp()}));
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), `${task("shared-proof")}/proofs/del-4`),
      {uploadedBy: "del-4", companyUID: CO, taskId: "shared-proof", imagePaths: []}));
    await assertSucceeds(setDoc(comp(db, "shared-proof", "del-4"), done()));
  });
  test("another company's delegate cannot write", async () => {
    const other = env.authenticatedContext("del-x", {role: "delegate", orgId: ORG, companyId: "other-co", delegateId: "del-x"})
      .firestore();
    await assertFails(setDoc(comp(other, "shared", "del-x"), done()));
  });
  test("staff of the company list everyone's completions", async () => {
    const hr = env.authenticatedContext("hr").firestore();
    const snap = await assertSucceeds(getDocs(collection(hr, `${task("shared")}/completions`)));
    if (snap.size < 1) throw new Error("expected completions");
  });
  test("individual task: delegate moves its own task, but not to cancelled", async () => {
    const db = asDel("del-1");
    await assertSucceeds(updateDoc(doc(db, task("own")), {status: "inProgress"}));
    await assertFails(updateDoc(doc(db, task("own")), {status: "cancelled"}));
    await assertFails(updateDoc(doc(db, task("own")), {completedBy: "del-9"}));
  });
});
