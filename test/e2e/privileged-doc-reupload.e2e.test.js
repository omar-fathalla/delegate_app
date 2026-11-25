/**
 * privilegedReuploadDelegateDocument against Firestore emulator (real admin).
 * npm run test:e2e:privileged-reupload
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../../functions/node_modules/firebase-admin");

let fn;
// TAS-23: the callables read the caller role and scope from the token claims.
const CLAIMS = {
  tech: {role: "technical_support"},
  sa: {role: "super-admin"},
  sup: {role: "supervisor", orgId: "o1", companyId: "c1"},
};
const ctx = (uid) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}, ...(CLAIMS[uid] || {})}}, rawRequest: {headers: {}}});

let db;
let BUCKET;
let storageUrl;

const delPath = (org, co, uid) => `organizations/${org}/companies/${co}/delegates/${uid}`;

function patchStorageExists() {
  const storage = admin.storage();
  const origBucket = storage.bucket.bind(storage);
  storage.bucket = (name) => {
    const bucket = origBucket(name);
    const origFile = bucket.file.bind(bucket);
    bucket.file = (path) => {
      const file = origFile(path);
      file.getMetadata = async () => [{name: path}];
      file.exists = async () => [true];
      return file;
    };
    return bucket;
  };
}

async function code(promise) {
  try {
    return {ok: true, data: await promise};
  } catch (e) {
    return {ok: false, code: e.code, reason: String(e.message || "")};
  }
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "run under the Firestore emulator");
  fn = require("../../functions/lib/index.js");
  patchStorageExists();
  db = admin.firestore();
  BUCKET = admin.storage().bucket().name;
  storageUrl = (uid, file) =>
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/delegate_documents%2F${uid}%2F${file}?alt=media`;

  const photoApproved = {
    documentKey: "personalPhoto",
    documentStatus: "approved",
    documentURL: storageUrl("d1", "personalPhoto_0.jpg"),
    uploadedAt: "2026-01-01",
    reviewedBy: "x",
    reviewedAt: "2026-01-01",
  };
  const baseActive = (org, co, uid, docs) => ({
    uid,
    status: "active",
    organizationUID: org,
    companyUID: co,
    phoneNumber: "01011111111",
    profileImageUrl: photoApproved.documentURL,
    personalPhotoURL: photoApproved.documentURL,
    photoURL: photoApproved.documentURL,
    documents: docs,
  });

  await db.doc("organizations/o1").set({name: "O1"});
  await db.doc("organizations/o1/companies/c1").set({name: "C1"});
  await db.doc("users/tech").set({role: "technical_support", organizationUID: "o1"});
  await db.doc("users/sa").set({role: "super-admin"});
  await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
  await db.doc(delPath("o1", "c1", "d1")).set(baseActive("o1", "c1", "d1", [photoApproved]));
  await db.doc(delPath("o1", "c1", "d-pend")).set({
    ...baseActive("o1", "c1", "d-pend", [{
      documentKey: "personalPhoto",
      documentStatus: "pending",
      documentURL: storageUrl("d-pend", "personalPhoto_0.jpg"),
      uploadedAt: "2026-01-01",
    }]),
    status: "pending",
  });
});

test.after(async () => { await Promise.all(admin.apps.map((a) => a && a.delete())); });

const callTech = (payload) =>
  fn.privilegedReuploadDelegateDocument.run(payload, ctx("tech"));

test("tech replaces photo as approved without flipping delegate status", async () => {
  const url = storageUrl("d1", "personalPhoto_new.jpg");
  const r = await callTech({
    uid: "d1",
    organizationUID: "o1",
    companyUID: "c1",
    docType: "personalPhoto",
    newUrl: url,
  });
  assert.equal(r.documentStatus, "approved");
  const data = (await db.doc(delPath("o1", "c1", "d1")).get()).data();
  assert.equal(data.status, "active");
});

test("tech approves pending photo via review mode", async () => {
  const r = await callTech({
    uid: "d-pend",
    organizationUID: "o1",
    companyUID: "c1",
    docType: "personalPhoto",
    approve: true,
  });
  assert.equal(r.documentStatus, "approved");
});

test("review mode rejects approving already-approved doc", async () => {
  const r = await code(callTech({
    uid: "d1",
    organizationUID: "o1",
    companyUID: "c1",
    docType: "personalPhoto",
    approve: true,
  }));
  assert.equal(r.ok, false);
  assert.match(String(r.code), /failed-precondition|not-found/);
});

test("rejects path traversal in storage URL", async () => {
  const url =
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
    "delegate_documents%2Fd1%2F..%2Fd2%2Fevil.jpg";
  const r = await code(callTech({
    uid: "d1",
    organizationUID: "o1",
    companyUID: "c1",
    docType: "personalPhoto",
    newUrl: url,
  }));
  assert.equal(r.ok, false);
  assert.match(String(r.code), /invalid-argument/);
});

test("rejects external storage URL", async () => {
  const r = await code(callTech({
    uid: "d1",
    organizationUID: "o1",
    companyUID: "c1",
    docType: "personalPhoto",
    newUrl: "https://cdn.example/evil.jpg",
  }));
  assert.equal(r.ok, false);
});

test("supervisor cannot call privileged reupload", async () => {
  const r = await code(fn.privilegedReuploadDelegateDocument.run({
    uid: "d1",
    organizationUID: "o1",
    companyUID: "c1",
    docType: "personalPhoto",
    newUrl: storageUrl("d1", "x.jpg"),
  }, ctx("sup")));
  assert.equal(r.ok, false);
  assert.match(String(r.code), /permission-denied/);
});