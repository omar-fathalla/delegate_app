const {test} = require("node:test");
const assert = require("node:assert/strict");

const L = require("../lib/privileged_delegate_doc_reupload_logic");

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
  assert.equal(out[0].documentURL, "https://cdn.example/new.jpg");
  assert.equal(out[0].reviewedBy, "tech1");
  assert.equal(out[1].documentStatus, "approved");
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
    L.decidePrivilegedDocReupload({uid: "t1", role: "technical_support"}, target, payload).ok,
    true,
  );
  assert.equal(
    L.decidePrivilegedDocReupload({uid: "s1", role: "supervisor"}, target, payload).reason,
    "caller_not_privileged_staff",
  );
});

const BUCKET = "practice-firebase-72df1.appspot.com";
const goodPath = (uid, file) =>
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/delegate_documents%2F${uid}%2F${file}?alt=media`;

test("resolveDelegateDocumentStorageObject accepts allowed bucket path", () => {
  const r = L.resolveDelegateDocumentStorageObject(
    goodPath("d1", "personalPhoto_1.jpg"),
    "d1",
  );
  assert.equal(r.ok, true);
  assert.equal(r.objectPath, "delegate_documents/d1/personalPhoto_1.jpg");
});

test("resolveDelegateDocumentStorageObject rejects foreign host", () => {
  const r = L.resolveDelegateDocumentStorageObject("https://cdn.example/x.jpg", "d1");
  assert.equal(r.ok, false);
  assert.equal(r.reason, "invalid_image_url");
});

test("resolveDelegateDocumentStorageObject rejects wrong delegate uid", () => {
  const r = L.resolveDelegateDocumentStorageObject(
    goodPath("d1", "personalPhoto_1.jpg"),
    "d2",
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "wrong_delegate_folder");
});

test("resolveDelegateDocumentStorageObject rejects evil bucket", () => {
  const r = L.resolveDelegateDocumentStorageObject(
    "https://firebasestorage.googleapis.com/v0/b/evil.appspot.com/o/delegate_documents%2Fd1%2Fx.jpg",
    "d1",
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "invalid_image_url");
});

test("applyPrivilegedDocumentReview approve and reject", () => {
  const raw = [
    {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "u1"},
  ];
  const approved = L.applyPrivilegedDocumentReview(raw, "personalPhoto", true, "tech", undefined, "t");
  assert.equal(approved[0].documentStatus, "approved");
  assert.equal(approved[0].reviewedBy, "tech");
  const rejected = L.applyPrivilegedDocumentReview(raw, "personalPhoto", false, "tech", "bad", "t");
  assert.equal(rejected[0].documentStatus, "rejected");
  assert.equal(rejected[0].rejectionReason, "bad");
});

test("decidePrivilegedDocReupload rejects org mismatch", () => {
  const target = {
    delegateUid: "d1",
    organizationUID: "o2",
    companyUID: "c1",
    status: "active",
  };
  assert.equal(
    L.decidePrivilegedDocReupload(
      {uid: "sa1", role: "superAdmin"},
      target,
      {organizationUID: "o1", companyUID: "c1"},
    ).reason,
    "out_of_scope",
  );
});