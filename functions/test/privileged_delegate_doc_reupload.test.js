const {test} = require("node:test");
const assert = require("node:assert/strict");

const L = require("../lib/privileged_delegate_doc_reupload_logic");

const DEFAULT_BUCKET = "practice-firebase-72df1.appspot.com";
const goodPath = (uid, file) =>
  `https://firebasestorage.googleapis.com/v0/b/${DEFAULT_BUCKET}/o/delegate_documents%2F${uid}%2F${file}?alt=media`;

test("mergePrivilegedReuploadedDocument marks approved with reviewer", () => {
  const raw = [
    {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "old"},
    {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f", secondaryURL: "b"},
  ];
  const out = L.mergePrivilegedReuploadedDocument(
    raw,
    "personalPhoto",
    "https://cdn.example/new.jpg",
    "2026-11-15",
    "tech1",
  );
  assert.equal(out[0].documentStatus, "approved");
  assert.equal(out[0].reviewedBy, "tech1");
});

test("resolveDelegateDocumentStorageObject accepts default bucket path", () => {
  const r = L.resolveDelegateDocumentStorageObject(
    goodPath("d1", "personalPhoto_1.jpg"),
    "d1",
    DEFAULT_BUCKET,
  );
  assert.equal(r.ok, true);
  assert.equal(r.objectPath, "delegate_documents/d1/personalPhoto_1.jpg");
});

test("rejects traversal segment in encoded HTTPS path", () => {
  const url =
    `https://firebasestorage.googleapis.com/v0/b/${DEFAULT_BUCKET}/o/` +
    "delegate_documents%2Fd1%2F..%2Fd2%2Fforeign.jpg";
  const r = L.resolveDelegateDocumentStorageObject(url, "d1", DEFAULT_BUCKET);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "path_traversal");
});

test("rejects double-encoded traversal", () => {
  const once = encodeURIComponent("delegate_documents/d1/../d2/x.jpg");
  const url =
    `https://firebasestorage.googleapis.com/v0/b/${DEFAULT_BUCKET}/o/${encodeURIComponent(once)}`;
  const r = L.resolveDelegateDocumentStorageObject(url, "d1", DEFAULT_BUCKET);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "path_traversal");
});

test("rejects foreign delegate folder after decode", () => {
  const r = L.resolveDelegateDocumentStorageObject(
    goodPath("d1", "personalPhoto_1.jpg"),
    "d2",
    DEFAULT_BUCKET,
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "wrong_delegate_folder");
});

test("rejects non-default allow-listed bucket", () => {
  const url =
    "https://firebasestorage.googleapis.com/v0/b/tashil-dev.appspot.com/o/" +
    "delegate_documents%2Fd1%2Fp.jpg";
  const r = L.resolveDelegateDocumentStorageObject(url, "d1", DEFAULT_BUCKET);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "wrong_bucket");
});

test("rejects external host", () => {
  const r = L.resolveDelegateDocumentStorageObject(
    "https://cdn.example/x.jpg",
    "d1",
    DEFAULT_BUCKET,
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "invalid_image_url");
});

test("applyPrivilegedDocumentReview approve and reject pending only", () => {
  const raw = [
    {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "u1"},
  ];
  const approved = L.applyPrivilegedDocumentReview(raw, "personalPhoto", true, "tech", undefined, "t");
  assert.equal(approved.ok, true);
  assert.equal(approved.documents[0].documentStatus, "approved");
  const rejected = L.applyPrivilegedDocumentReview(raw, "personalPhoto", false, "tech", "bad", "t");
  assert.equal(rejected.ok, true);
  assert.equal(rejected.documents[0].documentStatus, "rejected");
});

test("applyPrivilegedDocumentReview denies approving already approved", () => {
  const raw = [
    {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "u1", reviewedBy: "x"},
  ];
  const r = L.applyPrivilegedDocumentReview(raw, "personalPhoto", true, "tech", undefined, "t");
  assert.equal(r.ok, false);
  assert.equal(r.reason, "already_approved");
});

test("applyPrivilegedDocumentReview denies non-pending reject", () => {
  const raw = [
    {documentKey: "personalPhoto", documentStatus: "rejected", documentURL: "u1"},
  ];
  const r = L.applyPrivilegedDocumentReview(raw, "personalPhoto", false, "tech", "bad", "t");
  assert.equal(r.ok, false);
  assert.equal(r.reason, "not_pending");
});

test("decidePrivilegedDocReupload allows SA and tech", () => {
  const target = {
    delegateUid: "d1",
    organizationUID: "o1",
    companyUID: "c1",
    status: "active",
  };
  const payload = {organizationUID: "o1", companyUID: "c1"};
  assert.equal(
    L.decidePrivilegedDocReupload({uid: "sa1", role: "super-admin"}, target, payload).ok,
    true,
  );
  assert.equal(
    L.decidePrivilegedDocReupload({uid: "s1", role: "supervisor"}, target, payload).reason,
    "caller_not_privileged_staff",
  );
});