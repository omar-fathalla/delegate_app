/**
 * Emulator tests for storage.rules. Covers anonymous denial, intent-based
 * tenant checks, and the first-come claim race (clients cannot mint
 * intents; a missing intent denies staff of another company).
 */
"use strict";
const {describe, test, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc} = require("firebase/firestore");
const {ref, uploadBytes, getBytes, listAll} = require("firebase/storage");

function splitHost(envName, fallback) {
  const raw = process.env[envName] || fallback;
  const [host, port] = raw.split(":");
  return {host, port: Number(port)};
}

const bytes = Uint8Array.from(Buffer.from("tashil storage rules fixture\n"));

describe("storage.rules", () => {
  let env;
  const fsHost = splitHost("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080");
  const stHost = splitHost("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199");

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-tashil-storage",
      firestore: {
        host: fsHost.host,
        port: fsHost.port,
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
      storage: {
        host: stHost.host,
        port: stHost.port,
        rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8"),
      },
    });
  });

  after(async () => {
    if (env) await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/hrA"), {role: "hr", companyUID: "coA", organizationUID: "o1"});
      await setDoc(doc(db, "users/hrB"), {role: "hr", companyUID: "coB", organizationUID: "o2"});
      await setDoc(doc(db, "users/supA"), {role: "admin", companyUID: "coA", organizationUID: "o1"});
      await setDoc(doc(db, "users/dlgA"), {role: "delegate", companyUID: "coA", uid: "dlgA"});
      await setDoc(doc(db, "storage_upload_intents/folderA"), {companyUID: "coA", createdBy: "callable"});
      await setDoc(doc(db, "organizations/o1/companies/coA/delegates/dlgA"), {
        uid: "dlgA", companyUID: "coA", status: "active",
      });
    });
  });

  function storage(uid, provider) {
    return env.authenticatedContext(uid, {
      firebase: {sign_in_provider: provider || "password"},
    }).storage();
  }
  function path(store, p) {
    return ref(store, p);
  }

  test("anonymous is denied on documents, receipts, and other private paths", async () => {
    const anon = storage("anon1", "anonymous");
    await assertFails(getBytes(path(anon, "delegate_documents/folderA/x.jpg")));
    await assertFails(uploadBytes(path(anon, "delegate_documents/folderA/x.jpg"), bytes));
    await assertFails(getBytes(path(anon, "delegate_subscription_receipts/folderA/receipt.jpg")));
    await assertFails(uploadBytes(path(anon, "delegate_subscription_receipts/folderA/receipt.jpg"), bytes));
    await assertFails(uploadBytes(path(anon, "penalties/p1.jpg"), bytes));
    await assertFails(uploadBytes(path(anon, "leave_attachments/l1.jpg"), bytes));
    await assertFails(uploadBytes(path(anon, "staging/s1.bin"), bytes));
    await assertFails(uploadBytes(path(anon, "feedback_screenshots/f1.png"), bytes));
  });

  test("same-company staff can read and write a folder with a matching intent", async () => {
    const hr = storage("hrA");
    await assertSucceeds(uploadBytes(path(hr, "delegate_documents/folderA/profile.jpg"), bytes));
    await assertSucceeds(getBytes(path(hr, "delegate_documents/folderA/profile.jpg")));
    await assertSucceeds(listAll(path(hr, "delegate_documents/folderA")));
    await assertSucceeds(uploadBytes(path(hr, "delegate_subscription_receipts/folderA/receipt.jpg"), bytes));
  });

  test("other-company staff are denied even when they would claim first", async () => {
    const hrB = storage("hrB");
    // No intent they can mint; upload to a folder that has no intent yet
    // (legacy/web uid) must fail, and so must a folder owned by coA.
    await assertFails(uploadBytes(path(hrB, "delegate_documents/folderA/stolen.jpg"), bytes));
    await assertFails(getBytes(path(hrB, "delegate_documents/folderA/profile.jpg")));
    await assertFails(uploadBytes(path(hrB, "delegate_documents/dlgA/stolen.jpg"), bytes));
    await assertFails(uploadBytes(path(hrB, "delegate_documents/brand_new_id/x.jpg"), bytes));
  });

  test("folder owner can access their uid folder without an intent", async () => {
    const dlg = storage("dlgA");
    await assertSucceeds(uploadBytes(path(dlg, "delegate_documents/dlgA/profile.jpg"), bytes));
    await assertSucceeds(getBytes(path(dlg, "delegate_documents/dlgA/profile.jpg")));
  });

  test("same-company staff cannot access a legacy folder until an intent exists", async () => {
    const sup = storage("supA");
    await assertFails(getBytes(path(sup, "delegate_documents/dlgA/profile.jpg")));
  });

  test("same-company staff can access a legacy folder after an intent is backfilled", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "storage_upload_intents/dlgA"), {
        companyUID: "coA", createdBy: "backfill",
      });
    });
    const sup = storage("supA");
    await assertSucceeds(uploadBytes(path(sup, "delegate_documents/dlgA/profile.jpg"), bytes));
    await assertSucceeds(getBytes(path(sup, "delegate_documents/dlgA/profile.jpg")));
  });

  test("company file paths are tenant-scoped", async () => {
    const hrA = storage("hrA");
    const hrB = storage("hrB");
    await assertSucceeds(uploadBytes(path(hrA, "companies/coA/logo.png"), bytes));
    await assertFails(uploadBytes(path(hrB, "companies/coA/logo.png"), bytes));
  });

  test("other-company staff and delegates cannot use leftover private paths", async () => {
    const hrB = storage("hrB");
    const dlg = storage("dlgA");
    const hrA = storage("hrA");
    // Delegates are out of staff-only paths (penalties, leave, feedback, public write).
    await assertFails(uploadBytes(path(dlg, "penalties/p1.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "leave_attachments/l1.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/f1.png"), bytes));
    await assertFails(uploadBytes(path(dlg, "public/write.txt"), bytes));
    // Tenant-scoped paths: other-company staff denied; same-company staff allowed.
    await assertFails(uploadBytes(path(hrB, "delegates/folderA/x.jpg"), bytes));
    await assertFails(uploadBytes(path(hrB, "organizations/o1/companies/coA/delegates/folderA/id.jpg"), bytes));
    await assertFails(uploadBytes(path(hrB, "staging/requests/folderA/id.jpg"), bytes));
    await assertFails(uploadBytes(path(hrB, "companies/coA/logo.png"), bytes));
    await assertSucceeds(uploadBytes(path(hrA, "organizations/o1/companies/coA/delegates/folderA/id.jpg"), bytes));
    await assertSucceeds(uploadBytes(path(hrA, "penalties/p1.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "penalties/owned.jpg"), bytes));
  });

  test("unauthenticated is denied on private paths; public remains world-readable", async () => {
    const store = env.unauthenticatedContext().storage();
    await assertFails(uploadBytes(path(store, "delegate_documents/folderA/x.jpg"), bytes));
    await assertFails(getBytes(path(store, "delegate_documents/folderA/profile.jpg")));
    await assertFails(uploadBytes(path(store, "public/secret.txt"), bytes));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), "public/open.txt"), bytes);
    });
    await assertSucceeds(getBytes(path(store, "public/open.txt")));
  });
});

// Keep a named export so node --test counts the file even if helpers grow.
assert.ok(true);
