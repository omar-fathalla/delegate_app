const {test} = require("node:test");
const assert = require("node:assert/strict");

const L = require("../lib/supervisor_delegate_doc_reupload_logic");

test("mergeReuploadedDocument keeps photo at index 1", () => {
  const raw = [
    {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f", secondaryURL: "b"},
    {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "old"},
    {documentKey: "paymentReceipt", documentStatus: "approved", documentURL: "r"},
  ];
  const out = L.mergeReuploadedDocument(raw, "personalPhoto", "https://cdn.example/new.jpg", "2026-11-15");
  assert.equal(out.length, 3);
  assert.equal(out[1].documentKey, "personalPhoto");
  assert.equal(out[1].documentStatus, "pending");
  assert.equal(out[1].documentURL, "https://cdn.example/new.jpg");
  assert.equal(out[0].documentStatus, "approved");
});

test("mergeReuploadedDocument nationalityId front and back", () => {
  const raw = [
    {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "p"},
    {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f", secondaryURL: "b"},
  ];
  const front = L.mergeReuploadedDocument(raw, "nationalIdFront", "https://cdn.example/nf.jpg", "t");
  assert.equal(front[1].documentURL, "https://cdn.example/nf.jpg");
  assert.equal(front[1].documentStatus, "pending");
  const back = L.mergeReuploadedDocument(front, "nationalIdBack", "https://cdn.example/nb.jpg", "t");
  assert.equal(back[1].secondaryURL, "https://cdn.example/nb.jpg");
});

test("isKnownSupervisorReuploadDocType", () => {
  assert.equal(L.isKnownSupervisorReuploadDocType("personalPhoto"), true);
  assert.equal(L.isKnownSupervisorReuploadDocType("bogus"), false);
});

test("decideSupervisorDocReupload scope and active delegate", () => {
  const sup = {uid: "s", role: "supervisor", organizationUID: "o1", companyUID: "c1"};
  assert.equal(L.decideSupervisorDocReupload(sup, {
    delegateUid: "d1", organizationUID: "o1", companyUID: "c1", status: "active",
  }).ok, true);
  assert.equal(L.decideSupervisorDocReupload(sup, {
    delegateUid: "d1", organizationUID: "o2", companyUID: "c1", status: "active",
  }).reason, "out_of_scope");
  assert.equal(L.decideSupervisorDocReupload({uid: "hr", role: "hr"}, {
    delegateUid: "d1", organizationUID: "o1", companyUID: "c1", status: "active",
  }).reason, "caller_not_supervisor");
});
// TAS-373: only an ID card sends the delegate back to review.
test("TAS-373 reuploadSetsDelegatePending and idReviewRestoresActive", () => {
  const L2 = require("../lib/supervisor_delegate_doc_reupload_logic");
  assert.equal(L2.reuploadSetsDelegatePending("nationalIdFront"), true);
  assert.equal(L2.reuploadSetsDelegatePending("nationalIdBack"), true);
  assert.equal(L2.reuploadSetsDelegatePending("personalPhoto"), false);
  assert.equal(L2.reuploadSetsDelegatePending("paymentReceipt"), false);
  const id = (s) => [{documentKey: "nationalityId", documentStatus: s}];
  const d = {status: "pending", statusReason: "supervisor_id_reupload"};
  assert.equal(L2.idReviewRestoresActive(d, id("approved")), true);
  assert.equal(L2.idReviewRestoresActive(d, id("rejected")), false);
  assert.equal(L2.idReviewRestoresActive({status: "pending"}, id("approved")), false, "new delegate stays pending");
  assert.equal(L2.idReviewRestoresActive({...d, status: "suspended"}, id("approved")), false);
});
