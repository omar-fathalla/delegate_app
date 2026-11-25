/**
 * TAS-28 phase 0: firestore.rules and storage.rules name the delegate by the
 * delegateId claim (set by delegateLoginV2) and still accept the old
 * `request.auth.uid == delegate doc id` equality.
 *
 * Three delegate tokens for the same delegate doc d1:
 *   OLD    uid d1, no delegateId claim   (old token shape)
 *   TODAY  uid d1, delegateId d1         (every token minted today)
 *   PHASE1 uid dlg_x, delegateId d1      (phase 1: new uid, same doc)
 *   CLAIM_ONLY uid dlg_z, delegateId d1, no delegateIds (claim-only paths)
 * and an attacker whose claim names another delegate (uid dlg_y, claim d2).
 *
 * Run: npm run test:rules:tas28 (scripts/emulators_exec.sh picks free ports).
 */
"use strict";
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertFails, assertDeniedByRule, assertBudgetHeadroom,
} = require("./_rules_testing");
const {doc, setDoc, getDoc} = require("firebase/firestore");
const {ref, uploadBytes} = require("firebase/storage");

const FS_RULES = readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8");
const ST_RULES = readFileSync(resolve(__dirname, "../../storage.rules"), "utf8");

function splitHost(envName, fallback) {
  const raw = process.env[envName] || fallback;
  const [host, port] = raw.split(":");
  return {host, port: Number(port)};
}

const BASE = {role: "delegate", orgId: "o1", companyId: "c1", firebase: {sign_in_provider: "custom"}};
const TOKENS = {
  OLD: {uid: "d1", claims: {...BASE}},
  TODAY: {uid: "d1", claims: {...BASE, delegateId: "d1", delegateIds: ["d1"]}},
  // delegateLoginV2 always lists the primary id in delegateIds too.
  PHASE1: {uid: "dlg_x", claims: {...BASE, delegateId: "d1", delegateIds: ["d1"]}},
  // Claim only, no delegateIds: proves the paths that read the claim itself.
  CLAIM_ONLY: {uid: "dlg_z", claims: {...BASE, delegateId: "d1"}},
  ATTACKER: {uid: "dlg_y", claims: {...BASE, delegateId: "d2", delegateIds: ["d2"]}},
};
const OWNERS = ["OLD", "TODAY", "PHASE1", "CLAIM_ONLY"];

const png = Uint8Array.from(Buffer.from("tas28 fixture\n"));
const IMG = {contentType: "image/jpeg"};

describe("TAS-28 phase 0: delegate id from the claim, old uid equality kept", () => {
  let env;
  const fs = (who) => env.authenticatedContext(TOKENS[who].uid, TOKENS[who].claims).firestore();
  const st = (who) => env.authenticatedContext(TOKENS[who].uid, TOKENS[who].claims).storage();

  before(async () => {
    const fsHost = splitHost("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080");
    const stHost = splitHost("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199");
    env = await initializeTestEnvironment({
      projectId: "demo-tas28",
      firestore: {host: fsHost.host, port: fsHost.port, rules: FS_RULES},
      storage: {host: stHost.host, port: stHost.port, rules: ST_RULES},
    });
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "organizations/o1"), {name: "o1"});
      await setDoc(doc(db, "organizations/o1/companies/c1"), {name: "c1"});
      const del = {role: "delegate", organizationUID: "o1", companyUID: "c1", status: "active"};
      await setDoc(doc(db, "organizations/o1/companies/c1/delegates/d1"), {...del, uid: "d1", position: "supervisor"});
      await setDoc(doc(db, "organizations/o1/companies/c1/delegates/d2"), {...del, uid: "d2"});
      await setDoc(doc(db, "organizations/o1/companies/c1/delegates/d3"), {...del, uid: "d3"});
      // d2 is held: its own Storage writes are refused (hold looked up by claim).
      await setDoc(doc(db, "organizations/o1/companies/c1/delegates/d2"),
        {...del, uid: "d2", status: "suspended"});
      await setDoc(doc(db, "organizations/o1/tasks/t1"), {
        companyId: "c1", assignedTo: "d1", createdBy: "comp", title: "T", description: "B", status: "inProgress",
      });
      await setDoc(doc(db, "storage_upload_intents/task_d1_1.jpg"), {companyUID: "c1"});
      await setDoc(doc(db, "storage_upload_intents/task_dlg_x_1.jpg"), {companyUID: "c1"});
      await setDoc(doc(db, "storage_upload_intents/proof_d1_1.jpg"), {companyUID: "c1"});
    });
  });

  after(async () => {
    if (env) await env.cleanup();
  });

  describe("firestore", () => {
    test("own nested delegate doc: old, today and phase-1 tokens read it", async () => {
      for (const who of ["OLD", "TODAY", "PHASE1"]) {
        await assertSucceeds(getDoc(doc(fs(who), "organizations/o1/companies/c1/delegates/d1")));
      }
    });

    test("a token whose claim names d2 (not a supervisor) cannot read a colleague", async () => {
      // The supervisor lookup follows the claim (d2), not d1's supervisor copy.
      await assertDeniedByRule(getDoc(doc(fs("ATTACKER"), "organizations/o1/companies/c1/delegates/d3")));
    });

    test("supervisor reads its company's delegates: own copy looked up by the claim", async () => {
      // PHASE1 / CLAIM_ONLY have no doc at delegates/<uid>; only the claim finds d1.
      for (const who of OWNERS) {
        await assertSucceeds(getDoc(doc(fs(who), "organizations/o1/companies/c1/delegates/d3")));
      }
    });

    test("task proof: owner writes proofs/d1 with d1 paths (old, today, phase 1)", async () => {
      // Real delegate tokens always carry delegateIds (proofAssignedOk /
      // ownsDelegateId read it), so CLAIM_ONLY is not used here.
      for (const who of ["OLD", "TODAY", "PHASE1"]) {
        await assertSucceeds(setDoc(doc(fs(who), "organizations/o1/tasks/t1/proofs/d1"), {
          uploadedBy: "d1", companyUID: "c1", taskId: "t1",
          imagePaths: [`task_proof/c1/d1/proof_d1_${who}.jpg`],
        }));
        await assertSucceeds(getDoc(doc(fs(who), "organizations/o1/tasks/t1/proofs/d1")));
      }
    });

    test("task proof: another delegate's claim cannot write or read proofs/d1", async () => {
      await assertDeniedByRule(setDoc(doc(fs("ATTACKER"), "organizations/o1/tasks/t1/proofs/d1"), {
        uploadedBy: "d1", companyUID: "c1", taskId: "t1", imagePaths: ["task_proof/c1/d1/proof_d1_z.jpg"],
      }));
      await assertDeniedByRule(getDoc(doc(fs("ATTACKER"), "organizations/o1/tasks/t1/proofs/d1")));
    });

    test("task proof: uploadedBy and paths must match the proof doc id", async () => {
      await assertDeniedByRule(setDoc(doc(fs("PHASE1"), "organizations/o1/tasks/t1/proofs/d1"), {
        uploadedBy: "dlg_x", companyUID: "c1", taskId: "t1", imagePaths: ["task_proof/c1/d1/proof_d1_q.jpg"],
      }));
      await assertDeniedByRule(setDoc(doc(fs("PHASE1"), "organizations/o1/tasks/t1/proofs/d1"), {
        uploadedBy: "d1", companyUID: "c1", taskId: "t1", imagePaths: ["task_proof/c1/d2/proof_d2_q.jpg"],
      }));
    });

    test("notify supervisor: createdBy is the own id (old, today, phase 1); another id is refused", async () => {
      const note = (createdBy) => ({
        title: "t", body: "b", companyUID: "c1", delegateUid: "supervisor_c1", createdBy,
      });
      for (const who of OWNERS) {
        await assertSucceeds(setDoc(doc(fs(who), `notifications/n_${who}`), note("d1")));
      }
      // The old equality (uid) is still accepted for a phase-1 token.
      await assertSucceeds(setDoc(doc(fs("PHASE1"), "notifications/n_uid"), note("dlg_x")));
      await assertDeniedByRule(setDoc(doc(fs("ATTACKER"), "notifications/n_att"), note("d1")));
      await assertDeniedByRule(setDoc(doc(fs("OLD"), "notifications/n_old_other"), note("d2")));
    });
  });

  describe("storage", () => {
    test("task_images: owner folder by uid (old) or by claim (phase 1)", async () => {
      await assertSucceeds(uploadBytes(ref(st("TODAY"), "task_images/c1/d1/task_d1_1.jpg"), png, IMG));
      await assertSucceeds(uploadBytes(ref(st("OLD"), "task_images/c1/d1/task_d1_1.jpg"), png, IMG));
      await assertSucceeds(uploadBytes(ref(st("PHASE1"), "task_images/c1/d1/task_d1_1.jpg"), png, IMG));
      // Old equality still accepted for the phase-1 uid itself.
      await assertSucceeds(uploadBytes(ref(st("PHASE1"), "task_images/c1/dlg_x/task_dlg_x_1.jpg"), png, IMG));
    });

    test("task_images: someone else's folder or a mismatched name is refused", async () => {
      await assertFails(uploadBytes(ref(st("ATTACKER"), "task_images/c1/d1/task_d1_1.jpg"), png, IMG));
      await assertFails(uploadBytes(ref(st("PHASE1"), "task_images/c1/d1/task_dlg_x_1.jpg"), png, IMG));
    });

    test("task_proof: phase-1 token uploads under its claim folder", async () => {
      await assertSucceeds(uploadBytes(ref(st("PHASE1"), "task_proof/c1/d1/proof_d1_1.jpg"), png, IMG));
      await assertFails(uploadBytes(ref(st("ATTACKER"), "task_proof/c1/d1/proof_d1_1.jpg"), png, IMG));
    });

    test("delegate_documents/<own id>: old, today and phase-1 tokens", async () => {
      for (const who of OWNERS) {
        await assertSucceeds(uploadBytes(ref(st(who), `delegate_documents/d1/${who}.jpg`), png, IMG));
      }
      await assertFails(uploadBytes(ref(st("ATTACKER"), "delegate_documents/d1/x.jpg"), png, IMG));
    });

    test("leave_attachments/<co>/<own id>: claim folder ok, other folder refused", async () => {
      for (const who of OWNERS) {
        await assertSucceeds(uploadBytes(ref(st(who), `leave_attachments/c1/d1/${who}.jpg`), png, IMG));
      }
      await assertFails(uploadBytes(ref(st("PHASE1"), "leave_attachments/c1/d3/x.jpg"), png, IMG));
    });

    test("held delegate (d2) is refused: the hold is read from the claim's doc", async () => {
      // Before phase 0 the hold was looked up at delegates/<uid> = dlg_y (no
      // doc) and the write was let through.
      await assertFails(uploadBytes(ref(st("ATTACKER"), "leave_attachments/c1/d2/x.jpg"), png, IMG));
    });

    test("feedback and permission photo names: own uid or own claim", async () => {
      await assertSucceeds(uploadBytes(ref(st("TODAY"), "feedback_screenshots/feedback_d1_1.jpg"), png, IMG));
      await assertSucceeds(uploadBytes(ref(st("PHASE1"), "feedback_screenshots/feedback_d1_2.jpg"), png, IMG));
      await assertSucceeds(uploadBytes(ref(st("PHASE1"), "feedback_screenshots/feedback_dlg_x_2.jpg"), png, IMG));
      await assertFails(uploadBytes(ref(st("PHASE1"), "feedback_screenshots/feedback_d3_2.jpg"), png, IMG));
      await assertSucceeds(uploadBytes(
        ref(st("PHASE1"), "organizations/o1/companies/c1/permissions/p1/photo_d1_1.jpg"), png, IMG));
      await assertFails(uploadBytes(
        ref(st("PHASE1"), "organizations/o1/companies/c1/permissions/p1/photo_d3_1.jpg"), png, IMG));
    });
  });
});

describe("TAS-28 expression budget headroom", () => {
  // Measured 25 Nov 2026 on this branch; margins below the measurement.
  const PROOF_PAD = Number(process.env.RULES_BUDGET_PAD_TAS28_PROOF || 45);
  const NESTED_PAD = Number(process.env.RULES_BUDGET_PAD_TAS28_NESTED || 200);
  const seed = async (db) => {
    const del = {role: "delegate", organizationUID: "o1", companyUID: "c1", status: "active"};
    await db.doc("organizations/o1/companies/c1/delegates/d1").set({...del, uid: "d1", position: "supervisor"});
    await db.doc("organizations/o1/companies/c1/delegates/d3").set({...del, uid: "d3"});
    await db.doc("organizations/o1/tasks/t1").set({
      companyId: "c1", assignedTo: "d1", createdBy: "comp", title: "T", description: "B", status: "inProgress",
    });
  };

  test(`proofs create keeps ${PROOF_PAD} spare pad units (phase-1 token, 3 paths)`, async () => {
    await assertBudgetHeadroom({
      rules: FS_RULES,
      line: "allow create, update: if signedIn()\n            && isSelfId(uploaderUid)",
      pad: PROOF_PAD,
      projectId: "demo-tas28-budget-proof",
      seed,
      request: (e) => e.authenticatedContext(TOKENS.PHASE1.uid, TOKENS.PHASE1.claims).firestore()
        .doc("organizations/o1/tasks/t1/proofs/d1").set({
          uploadedBy: "d1", companyUID: "c1", taskId: "t1",
          imagePaths: ["a", "b", "c"].map((t) => `task_proof/c1/d1/proof_d1_${t}.jpg`),
        }),
    });
  });

  test(`nested delegate read keeps ${NESTED_PAD} spare pad units (phase-1 supervisor reads a colleague)`, async () => {
    const line = "allow read: if signedIn() && canReadNestedDelegate(orgId, compId, delegateId);";
    await assertBudgetHeadroom({
      rules: FS_RULES,
      line,
      pad: NESTED_PAD,
      projectId: "demo-tas28-budget-nested",
      seed,
      request: (e) => e.authenticatedContext(TOKENS.PHASE1.uid, TOKENS.PHASE1.claims).firestore()
        .doc("organizations/o1/companies/c1/delegates/d3").get(),
    });
  });
});
