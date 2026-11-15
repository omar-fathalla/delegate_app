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