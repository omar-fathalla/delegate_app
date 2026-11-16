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
const {ref, uploadBytes, getBytes, listAll, deleteObject} = require("firebase/storage");

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
      await setDoc(doc(db, "users/dlgB"), {role: "delegate", companyUID: "coA", uid: "dlgB"});
      await setDoc(doc(db, "users/dlgOther"), {role: "delegate", companyUID: "coB", uid: "dlgOther"});
      await setDoc(doc(db, "users/dlgBare"), {role: "delegate", companyUID: "coA", uid: "dlgBare"});
      await setDoc(doc(db, "users/accA"), {role: "accountant", companyUID: "coA", organizationUID: "o1"});
      await setDoc(doc(db, "users/mkA"), {role: "marketing", companyUID: "coA", organizationUID: "o1"});
      await setDoc(doc(db, "storage_upload_intents/folderA"), {companyUID: "coA", createdBy: "callable"});
      await setDoc(doc(db, "organizations/o1/companies/coA/delegates/dlgA"), {
        uid: "dlgA", companyUID: "coA", status: "active",
      });
    });
  });

  function storage(uid, provider, claims) {
    return env.authenticatedContext(uid, {
      firebase: {sign_in_provider: provider || "password"},
      ...(claims || {}),
    }).storage();
  }
  function delegateTok(uid, companyId, extra) {
    return storage(uid, "password", {
      role: "delegate",
      delegateId: uid,
      companyId,
      ...(extra || {}),
    });
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

  test("same-company staff can access legacy uid folder via users/{uid} company (no intent)", async () => {
    const sup = storage("supA");
    await assertSucceeds(uploadBytes(path(sup, "delegate_documents/dlgA/profile.jpg"), bytes));
    await assertSucceeds(getBytes(path(sup, "delegate_documents/dlgA/profile.jpg")));
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

  test("delegates can upload permission photos, leave attachments, and feedback", async () => {
    const dlg = delegateTok("dlgA", "coA");
    // Distinct uids: the emulator reuses custom claims on the same auth
    // uid within a test, so dlgA cannot also stand in as a coB token.
    const dlgOtherCo = delegateTok("dlgOther", "coB");
    const dlgB = delegateTok("dlgB", "coA");
    const hrA = storage("hrA");
    const hrB = storage("hrB");
    await assertSucceeds(uploadBytes(path(dlg, "organizations/o1/companies/coA/permissions/p1/photo_1.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "organizations/o1/companies/coB/permissions/p1/photo_1.jpg"), bytes));
    await assertFails(uploadBytes(path(dlgOtherCo, "organizations/o1/companies/coA/permissions/p1/photo_1.jpg"), bytes));
    await assertSucceeds(uploadBytes(path(dlg, "leave_attachments/coA/dlgA/sick.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "leave_attachments/coA/otherUid/sick.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "leave_attachments/coB/dlgA/sick.jpg"), bytes));
    await assertFails(uploadBytes(path(dlgB, "leave_attachments/coA/dlgA/sick.jpg"), bytes));
    await assertSucceeds(uploadBytes(path(hrA, "leave_attachments/coA/dlgA/staff.jpg"), bytes));
    await assertFails(uploadBytes(path(hrB, "leave_attachments/coA/dlgA/staff.jpg"), bytes));
    const ownFb = {customMetadata: {userId: "dlgA"}};
    // N2: metadata alone is not enough; the filename must be feedback_{uid}_*.
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/dlgA-fb.png"), bytes, ownFb));
    await assertSucceeds(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_fb.png"), bytes, ownFb));
    // A password session without role=delegate is not a delegate upload.
    // Use a fresh uid so the emulator does not reuse dlgA's custom claims.
    await assertFails(uploadBytes(path(storage("dlgBare"), "feedback_screenshots/no-claim.png"), bytes, {customMetadata: {userId: "dlgBare"}}));
    await assertFails(uploadBytes(path(storage("accA"), "organizations/o1/companies/coA/delegates/folderA/id.jpg"), bytes));
    await assertFails(uploadBytes(path(storage("mkA"), "organizations/o1/companies/coA/delegates/folderA/id.jpg"), bytes));
    // Accountant/marketing keep same-company access to other org/company files.
    await assertSucceeds(uploadBytes(path(storage("accA"), "organizations/o1/companies/coA/other/note.txt"), bytes));
    await assertSucceeds(uploadBytes(path(storage("mkA"), "organizations/o1/companies/coA/other/note2.txt"), bytes));
    // F6: accountant/marketing cannot use leave attachments.
    await assertFails(uploadBytes(path(storage("accA"), "leave_attachments/coA/dlgA/acc.jpg"), bytes));
    await assertFails(uploadBytes(path(storage("mkA"), "leave_attachments/coA/dlgA/mk.jpg"), bytes));
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
    await assertSucceeds(uploadBytes(path(hrA, "penalties/coA/evidence/p1/file.jpg"), bytes));
    await assertSucceeds(uploadBytes(path(hrA, "penalties/evidence/legacy-write.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "penalties/owned.jpg"), bytes));
    await assertFails(uploadBytes(path(dlg, "penalties/coA/evidence/p1/dlg.jpg"), bytes));
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

  test("delegates only create feedback they own and cannot overwrite others", async () => {
    const dlg = delegateTok("dlgA", "coA");
    const dlgB = delegateTok("dlgB", "coA");
    const hrA = storage("hrA");
    const own = {customMetadata: {userId: "dlgA"}};
    const spoof = {customMetadata: {userId: "hrA"}};
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/no-meta.png"), bytes));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/spoof.png"), bytes, spoof));
    await assertSucceeds(uploadBytes(path(hrA, "feedback_screenshots/staff.png"), bytes, {customMetadata: {userId: "hrA"}}));
    await assertFails(getBytes(path(dlg, "feedback_screenshots/staff.png")));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/staff.png"), bytes, own));
    // Create now requires feedback_{uid}_*; a random name with own metadata is denied.
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/dlgA-own.png"), bytes, own));
    await assertSucceeds(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_own.png"), bytes, own));
    await assertSucceeds(getBytes(path(dlg, "feedback_screenshots/feedback_dlgA_own.png")));
    await assertSucceeds(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_named.png"), bytes));
    await assertSucceeds(getBytes(path(dlg, "feedback_screenshots/feedback_dlgA_named.png")));
    await assertFails(getBytes(path(dlgB, "feedback_screenshots/feedback_dlgA_named.png")));
    await assertFails(getBytes(path(dlgB, "feedback_screenshots/feedback_dlgA_own.png")));
    await assertFails(uploadBytes(path(dlgB, "feedback_screenshots/feedback_dlgA_own.png"), bytes, {customMetadata: {userId: "dlgB"}}));
    await assertSucceeds(getBytes(path(hrA, "feedback_screenshots/feedback_dlgA_own.png")));
  });

  test("feedback N1/N2 filename and metadata spoofing", async () => {
    const dlg = delegateTok("dlgA", "coA");
    const dlgB = delegateTok("dlgB", "coA");
    const hrA = storage("hrA");
    const own = {customMetadata: {userId: "dlgA"}};
    const otherMeta = {customMetadata: {userId: "dlgB"}};
    // Create: name must be feedback_{uid}_* (uid then '_').
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA.png"), bytes, own));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgAx_1.png"), bytes, own));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgB_x.png"), bytes, own));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/random.png"), bytes, own));
    // Create: if userId metadata is present it must equal the caller.
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_spoofmeta.png"), bytes, otherMeta));
    await assertSucceeds(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_ok.png"), bytes, own));
    await assertSucceeds(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_nometa.png"), bytes));
    // Conflicting metadata on a filename the caller would otherwise own.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(
        ref(ctx.storage(), "feedback_screenshots/feedback_dlgA_conflict.png"),
        bytes,
        {customMetadata: {userId: "dlgB"}},
      );
      await uploadBytes(
        ref(ctx.storage(), "feedback_screenshots/legacy_dlgA.png"),
        bytes,
        {customMetadata: {userId: "dlgA"}},
      );
      await uploadBytes(ref(ctx.storage(), "feedback_screenshots/legacy_none.png"), bytes);
      await uploadBytes(
        ref(ctx.storage(), "feedback_screenshots/feedback_dlgB_taggedA.png"),
        bytes,
        {customMetadata: {userId: "dlgA"}},
      );
    });
    await assertFails(getBytes(path(dlg, "feedback_screenshots/feedback_dlgA_conflict.png")));
    await assertFails(getBytes(path(dlgB, "feedback_screenshots/feedback_dlgA_conflict.png")));
    await assertFails(uploadBytes(path(dlg, "feedback_screenshots/feedback_dlgA_conflict.png"), bytes, own));
    await assertFails(deleteObject(path(dlg, "feedback_screenshots/feedback_dlgA_conflict.png")));
    // Legacy object: not feedback_{other}_* and userId == caller → read/update/delete.
    await assertSucceeds(getBytes(path(dlg, "feedback_screenshots/legacy_dlgA.png")));
    await assertFails(getBytes(path(dlgB, "feedback_screenshots/legacy_dlgA.png")));
    await assertSucceeds(uploadBytes(path(dlg, "feedback_screenshots/legacy_dlgA.png"), bytes, own));
    await assertSucceeds(deleteObject(path(dlg, "feedback_screenshots/legacy_dlgA.png")));
    await assertFails(getBytes(path(dlg, "feedback_screenshots/legacy_none.png")));
    // Filename is another uid's; metadata saying caller does not grant access.
    await assertFails(getBytes(path(dlg, "feedback_screenshots/feedback_dlgB_taggedA.png")));
    await assertFails(getBytes(path(dlgB, "feedback_screenshots/feedback_dlgB_taggedA.png")));
    await assertSucceeds(deleteObject(path(dlg, "feedback_screenshots/feedback_dlgA_ok.png")));
    await assertFails(deleteObject(path(dlgB, "feedback_screenshots/feedback_dlgA_nometa.png")));
    await assertSucceeds(getBytes(path(hrA, "feedback_screenshots/feedback_dlgA_conflict.png")));
  });

  test("penalty evidence is company-scoped for new uploads; legacy stays readable", async () => {
    const hrA = storage("hrA");
    const hrB = storage("hrB");
    const dlg = delegateTok("dlgA", "coA");
    await assertSucceeds(uploadBytes(path(hrA, "penalties/coA/evidence/pen1/a.jpg"), bytes));
    await assertFails(uploadBytes(path(hrB, "penalties/coA/evidence/pen1/b.jpg"), bytes));
    await assertSucceeds(uploadBytes(path(hrB, "penalties/coB/evidence/pen2/c.jpg"), bytes));
    await assertFails(getBytes(path(hrB, "penalties/coA/evidence/pen1/a.jpg")));
    // TA-60: v1.14.2 supervisors may still upload legacy evidence paths.
    await assertSucceeds(uploadBytes(path(hrA, "penalties/evidence/legacy-new.jpg"), bytes));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), "penalties/evidence/legacy.jpg"), bytes);
    });
    await assertSucceeds(getBytes(path(hrA, "penalties/evidence/legacy.jpg")));
    await assertSucceeds(getBytes(path(hrB, "penalties/evidence/legacy.jpg")));
    await assertSucceeds(uploadBytes(path(hrA, "penalties/evidence/legacy-overwrite.jpg"), bytes));
    await assertFails(getBytes(path(dlg, "penalties/coA/evidence/pen1/a.jpg")));
  });

  test("same-company delegates cannot overwrite or delete a colleague permission photo", async () => {
    const dlg = delegateTok("dlgA", "coA");
    const dlgB = delegateTok("dlgB", "coA");
    const hrA = storage("hrA");
    const hrB = storage("hrB");
    const owned = "organizations/o1/companies/coA/permissions/p1/photo_dlgA_1.jpg";
    const legacy = "organizations/o1/companies/coA/permissions/p1/photo_99.jpg";
    const meta = {customMetadata: {userId: "dlgA", delegateUid: "dlgA"}, contentType: "image/jpeg"};
    await assertSucceeds(uploadBytes(path(dlg, owned), bytes, meta));
    await assertSucceeds(uploadBytes(path(dlg, legacy), bytes));
    await assertSucceeds(getBytes(path(dlgB, owned)));
    await assertFails(uploadBytes(path(dlgB, owned), bytes));
    await assertFails(uploadBytes(path(dlgB, legacy), bytes));
    await assertFails(deleteObject(path(dlgB, owned)));
    await assertFails(deleteObject(path(dlg, legacy)));
    await assertSucceeds(deleteObject(path(dlg, owned)));
    await assertSucceeds(uploadBytes(path(hrA, "organizations/o1/companies/coA/permissions/p1/photo_dlgA_2.jpg"), bytes, meta));
    await assertSucceeds(deleteObject(path(hrA, "organizations/o1/companies/coA/permissions/p1/photo_dlgA_2.jpg")));
    await assertFails(uploadBytes(path(hrB, owned), bytes));
  });

  test("N1-r permission photo requires image contentType", async () => {
    const dlg = delegateTok("dlgA", "coA");
    const photo = "organizations/o1/companies/coA/permissions/p1/photo_dlgA_ct.jpg";
    const bad = {customMetadata: {userId: "dlgA", delegateUid: "dlgA"}, contentType: "application/pdf"};
    const good = {customMetadata: {userId: "dlgA", delegateUid: "dlgA"}, contentType: "image/jpeg"};
    await assertFails(uploadBytes(path(dlg, photo), bytes, bad));
    await assertSucceeds(uploadBytes(path(dlg, photo), bytes, good));
  });

  test("N1-r permission photo uid is exact, not a prefix", async () => {
    const dlg = delegateTok("dlgA", "coA");
    const dlgA2 = delegateTok("dlgA_2", "coA");
    const colliding = "organizations/o1/companies/coA/permissions/p1/photo_dlgA_2_99.jpg";
    const ownA = "organizations/o1/companies/coA/permissions/p1/photo_dlgA_99.jpg";
    const metaA2 = {customMetadata: {userId: "dlgA_2", delegateUid: "dlgA_2"}, contentType: "image/jpeg"};
    const metaA = {customMetadata: {userId: "dlgA", delegateUid: "dlgA"}, contentType: "image/jpeg"};
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), colliding), bytes, metaA2);
    });
    // dlgA must not create, overwrite, or delete photo_dlgA_2_*.
    await assertFails(uploadBytes(path(dlg, colliding), bytes, metaA));
    await assertFails(deleteObject(path(dlg, colliding)));
    await assertSucceeds(uploadBytes(path(dlg, ownA), bytes, metaA));
    await assertSucceeds(uploadBytes(path(dlgA2, colliding), bytes, metaA2));
    await assertSucceeds(deleteObject(path(dlgA2, colliding)));
    await assertSucceeds(deleteObject(path(dlg, ownA)));
  });

  test("held delegate cannot write leave, feedback, or permission photos", async () => {
    const heldTok = delegateTok("dlgHeld", "coA", {orgId: "o1"});
    const activeTok = delegateTok("dlgA", "coA", {orgId: "o1"});
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "organizations/o1/companies/coA/delegates/dlgHeld"), {
        uid: "dlgHeld", companyUID: "coA", organizationUID: "o1",
        status: "suspended", statusReason: "admin_suspend",
        holds: {admin_suspend: {at: "2026-11-11"}},
      });
    });
    const fb = "feedback_screenshots/feedback_dlgHeld_1.jpg";
    const leave = "leave_attachments/coA/dlgHeld/sick.jpg";
    const photo = "organizations/o1/companies/coA/permissions/p1/photo_dlgHeld_1.jpg";
    const meta = {customMetadata: {userId: "dlgHeld", delegateUid: "dlgHeld"}, contentType: "image/jpeg"};
    await assertFails(uploadBytes(path(heldTok, fb), bytes, meta));
    await assertFails(uploadBytes(path(heldTok, leave), bytes));
    await assertFails(uploadBytes(path(heldTok, photo), bytes, meta));
    await assertSucceeds(uploadBytes(path(activeTok, "feedback_screenshots/feedback_dlgA_heldcheck.jpg"), bytes));
    await assertSucceeds(uploadBytes(path(activeTok, "leave_attachments/coA/dlgA/heldcheck.jpg"), bytes));
  });

  test("task images: upload requires intent and exact N1-r name; client reads are denied", async () => {
    const imageBytes = Uint8Array.from(Buffer.from("fake-jpeg"));
    const meta = {contentType: "image/jpeg"};
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "storage_upload_intents/task_supA_1.jpg"), {
        companyUID: "coA", createdBy: "callable", purpose: "task_image",
      });
    });
    const sup = storage("supA");
    const hr = storage("hrA");
    const dlg = delegateTok("dlgA", "coA", {orgId: "o1"});
    const otherCo = storage("hrB");
    const owned = "task_images/coA/supA/task_supA_1.jpg";
    const colliding = "task_images/coA/supA/task_supA_2_1.jpg";
    const otherUid = "task_images/coA/supA/task_hrA_1.jpg";
    const otherCompany = "task_images/coB/supA/task_supA_1.jpg";
    const noIntent = "task_images/coA/supA/task_supA_99.jpg";

    await assertSucceeds(uploadBytes(path(sup, owned), imageBytes, meta));
    await assertFails(uploadBytes(path(sup, colliding), imageBytes, meta));
    await assertFails(uploadBytes(path(sup, otherUid), imageBytes, meta));
    await assertFails(uploadBytes(path(sup, otherCompany), imageBytes, meta));
    await assertFails(uploadBytes(path(sup, noIntent), imageBytes, meta));
    await assertFails(uploadBytes(path(hr, "task_images/coA/hrA/task_hrA_1.jpg"), imageBytes, meta));
    await assertFails(uploadBytes(path(otherCo, owned), imageBytes, meta));

    await assertFails(getBytes(path(sup, owned)));
    await assertFails(getBytes(path(hr, owned)));
    await assertFails(getBytes(path(dlg, owned)));
    await assertFails(getBytes(path(otherCo, owned)));
    await assertFails(listAll(path(sup, "task_images/coA/supA")));

    await assertFails(deleteObject(path(hr, owned)));
    await assertSucceeds(deleteObject(path(sup, owned)));
  });

  test("legacy task image path is closed for create and client reads, even to org staff", async () => {
    const imageBytes = Uint8Array.from(Buffer.from("fake-jpeg"));
    const meta = {contentType: "image/jpeg"};
    const legacy = "organizations/o1/task_images/supA/legacy.jpg";
    const sup = storage("supA");
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), legacy), imageBytes, meta);
    });
    await assertFails(getBytes(path(sup, legacy)));
    await assertFails(uploadBytes(path(sup, "organizations/o1/task_images/supA/task_supA_new.jpg"), imageBytes, meta));
    await assertSucceeds(deleteObject(path(sup, legacy)));
  });

  test("task proof photos: upload requires intent and exact N1-r name; client reads are denied", async () => {
    const imageBytes = Uint8Array.from(Buffer.from("fake-jpeg"));
    const meta = {contentType: "image/jpeg"};
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "storage_upload_intents/proof_dlgA_1.jpg"), {
        companyUID: "coA", createdBy: "callable", purpose: "task_proof_image",
      });
    });
    const dlg = delegateTok("dlgA", "coA", {orgId: "o1"});
    const other = delegateTok("dlgB", "coA", {orgId: "o1"});
    const sup = storage("supA");
    const owned = "task_proof/coA/dlgA/proof_dlgA_1.jpg";
    const colliding = "task_proof/coA/dlgA/proof_dlgA_2_1.jpg";
    const otherUid = "task_proof/coA/dlgA/proof_dlgB_1.jpg";
    const otherCompany = "task_proof/coB/dlgA/proof_dlgA_1.jpg";
    const noIntent = "task_proof/coA/dlgA/proof_dlgA_99.jpg";
    const confused = "task_images/coA/dlgA/proof_dlgA_1.jpg";

    await assertSucceeds(uploadBytes(path(dlg, owned), imageBytes, meta));
    await assertFails(uploadBytes(path(dlg, colliding), imageBytes, meta));
    await assertFails(uploadBytes(path(dlg, otherUid), imageBytes, meta));
    await assertFails(uploadBytes(path(dlg, otherCompany), imageBytes, meta));
    await assertFails(uploadBytes(path(dlg, noIntent), imageBytes, meta));
    await assertFails(uploadBytes(path(other, owned), imageBytes, meta));
    await assertFails(uploadBytes(path(sup, owned), imageBytes, meta));

    await assertFails(getBytes(path(dlg, owned)));
    await assertFails(getBytes(path(sup, owned)));
    await assertFails(getBytes(path(other, owned)));
    await assertFails(listAll(path(dlg, "task_proof/coA/dlgA")));

    await assertFails(deleteObject(path(other, owned)));
    await assertSucceeds(deleteObject(path(dlg, owned)));
    await assertFails(uploadBytes(path(dlg, confused), imageBytes, meta));
  });

});

// Keep a named export so node --test counts the file even if helpers grow.
assert.ok(true);
