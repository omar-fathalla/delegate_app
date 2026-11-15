/**
 * supervisorReuploadDelegateDocument against Firestore emulator (real admin).
 *   npm run test:e2e:supervisor-reupload
 *
 * App path (profile_screen supervisor «تعديل / استبدال»): ensureStorageUploadIntent
 * for folderId=delegate uid + companyUID, then Storage upload under
 * delegate_documents/{uid}/, then this callable with newUrl. Storage rules deny
 * staff writes without a matching intent (see storage.rules + smoke_tashil_dev_storage_upload.js).
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../../functions/node_modules/firebase-admin");

let fn;
const ctx = (uid) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}}}, rawRequest: {headers: {}}});

let db;

const delPath = (org, co, uid) => `organizations/${org}/companies/${co}/delegates/${uid}`;

const PHOTO = {
  documentKey: "personalPhoto",
  documentStatus: "approved",
  documentURL: "https://cdn.example/p0.jpg",
  uploadedAt: "2026-01-01",
};
const NID = {
  documentKey: "nationalityId",
  documentStatus: "approved",
  documentURL: "https://cdn.example/id-f.jpg",
  secondaryURL: "https://cdn.example/id-b.jpg",
  uploadedAt: "2026-01-01",
};
const RCPT = {
  documentKey: "paymentReceipt",
  documentStatus: "approved",
  documentURL: "https://cdn.example/r.jpg",
  uploadedAt: "2026-01-01",
};
const DOCS_3 = [PHOTO, NID, RCPT];
const DOCS_PHOTO_INDEX_1 = [NID, {...PHOTO}, RCPT];
const DOCS_5 = [
  {documentKey: "authorizationLetter", documentStatus: "approved", documentURL: "a"},
  NID,
  {...PHOTO, documentURL: "https://cdn.example/p-mid.jpg"},
  RCPT,
  {documentKey: "insuranceLetter", documentStatus: "approved", documentURL: "i"},
];

const baseActive = (org, co, uid, documents) => ({
  uid,
  status: "active",
  organizationUID: org,
  companyUID: co,
  phoneNumber: "01011111111",
  profileImageUrl: PHOTO.documentURL,
  personalPhotoURL: PHOTO.documentURL,
  photoURL: PHOTO.documentURL,
  nationalIdFrontUrl: NID.documentURL,
  nationalIdBackUrl: NID.secondaryURL,
  receiptImageUrl: RCPT.documentURL,
  documents,
});

async function code(promise) {
  try {
    return {ok: true, data: await promise};
  } catch (e) {
    const msg = String(e.message || "");
    return {
      ok: false,
      code: e.code,
      reason: e.details?.reason || (msg.includes("unknown_doc_type") ? "unknown_doc_type" : msg),
    };
  }
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "run under the Firestore emulator");
  fn = require("../../functions/lib/index.js");
  db = admin.firestore();
  await db.doc("organizations/o1").set({name: "O1"});
  await db.doc("organizations/o2").set({name: "O2"});
  await db.doc("organizations/o1/companies/c1").set({name: "C1"});
  await db.doc("organizations/o2/companies/c1").set({name: "C1-o2"});
  await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
  await db.doc("users/d1").set({role: "delegate", organizationUID: "o1", companyUID: "c1"});
  await db.doc(delPath("o1", "c1", "d1")).set(baseActive("o1", "c1", "d1", [...DOCS_3]));
  await db.doc(delPath("o1", "c1", "d-mid")).set(baseActive("o1", "c1", "d-mid", [...DOCS_PHOTO_INDEX_1]));
  await db.doc(delPath("o1", "c1", "d5")).set(baseActive("o1", "c1", "d5", [...DOCS_5]));
  await db.doc(delPath("o2", "c1", "d-spoof")).set(baseActive("o2", "c1", "d-spoof", [...DOCS_3]));
});

test.after(async () => { await Promise.all(admin.apps.map((a) => a && a.delete())); });

const call = (payload) =>
  fn.supervisorReuploadDelegateDocument.run(payload, ctx("sup"));

async function docEntry(org, co, uid, key) {
  const docs = (await db.doc(delPath(org, co, uid)).get()).get("documents") || [];
  return docs.find((d) => d.documentKey === key);
}

test("photo at index 0 on [photo, nationalityId, receipt]", async () => {
  const url = "https://cdn.example/p-new.jpg";
  const r = await call({uid: "d1", organizationUID: "o1", companyUID: "c1", docType: "personalPhoto", newUrl: url});
  assert.equal(r.status, "pending");
  const data = (await db.doc(delPath("o1", "c1", "d1")).get()).data();
  assert.equal(data.status, "pending");
  const e = await docEntry("o1", "c1", "d1", "personalPhoto");
  assert.equal(e.documentStatus, "pending");
  assert.equal(e.documentURL, url);
  assert.equal(data.profileImageUrl, url);
});

test("ID front replace", async () => {
  await db.doc(delPath("o1", "c1", "d1")).set(baseActive("o1", "c1", "d1", [...DOCS_3]));
  const url = "https://cdn.example/id-f-new.jpg";
  await call({uid: "d1", docType: "nationalIdFront", newUrl: url});
  const e = await docEntry("o1", "c1", "d1", "nationalityId");
  assert.equal(e.documentStatus, "pending");
  assert.equal(e.documentURL, url);
});

test("ID back replace", async () => {
  await db.doc(delPath("o1", "c1", "d1")).set(baseActive("o1", "c1", "d1", [...DOCS_3]));
  const url = "https://cdn.example/id-b-new.jpg";
  await call({uid: "d1", docType: "nationalIdBack", newUrl: url});
  const e = await docEntry("o1", "c1", "d1", "nationalityId");
  assert.equal(e.documentStatus, "pending");
  assert.equal(e.secondaryURL, url);
});

test("photo not at index 0", async () => {
  const url = "https://cdn.example/p-mid-new.jpg";
  await call({uid: "d-mid", docType: "personalPhoto", newUrl: url});
  const e = await docEntry("o1", "c1", "d-mid", "personalPhoto");
  assert.equal(e.documentStatus, "pending");
  assert.equal(e.documentURL, url);
  assert.equal((await db.doc(delPath("o1", "c1", "d-mid")).get()).get("status"), "pending");
});

test("five-document list", async () => {
  const url = "https://cdn.example/p5-new.jpg";
  await call({uid: "d5", docType: "personalPhoto", newUrl: url});
  const e = await docEntry("o1", "c1", "d5", "personalPhoto");
  assert.equal(e.documentURL, url);
  assert.equal(e.documentStatus, "pending");
  const data = (await db.doc(delPath("o1", "c1", "d5")).get()).data();
  assert.equal(data.documents.length, 5);
});

test("unknown docType rejected before write", async () => {
  const before = (await db.doc(delPath("o1", "c1", "d1")).get()).data();
  const r = await code(call({uid: "d1", docType: "notARealType", newUrl: "https://x/y.jpg"}));
  assert.equal(r.ok, false);
  assert.match(String(r.code), /invalid-argument/);
  assert.equal(r.reason, "unknown_doc_type");
  const after = (await db.doc(delPath("o1", "c1", "d1")).get()).data();
  assert.equal(after.status, before.status);
  assert.deepEqual(after.documents, before.documents);
});

test("supervisor o1 cannot reupload delegate that exists only under o2", async () => {
  const before = (await db.doc(delPath("o2", "c1", "d-spoof")).get()).data();
  const r = await code(call({
    uid: "d-spoof",
    organizationUID: "o2",
    companyUID: "c1",
    docType: "personalPhoto",
    newUrl: "https://cdn.example/evil.jpg",
  }));
  assert.equal(r.ok, false);
  const after = (await db.doc(delPath("o2", "c1", "d-spoof")).get()).data();
  assert.equal(after.status, before.status);
  assert.deepEqual(after.documents, before.documents);
});