const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/invite_email_index_logic");

test("index doc id is normalized email", () => {
  assert.equal(L.inviteEmailIndexDocId("  Foo@X.TEST "), "foo@x.test");
});

test("pending invite maps to index payload", () => {
  const p = L.inviteEmailIndexFromInvite("inv1", {
    email: "a@b.c",
    status: "pending",
    organizationId: "o1",
    companyId: "c1",
    roleToAssign: "company-admin",
  });
  assert.deepEqual(p, {
    inviteId: "inv1",
    organizationUID: "o1",
    companyUID: "c1",
    role: "company-admin",
    status: "pending",
  });
});

test("non-pending invite yields no index", () => {
  assert.equal(
    L.inviteEmailIndexFromInvite("inv1", {email: "a@b.c", status: "claimed"}),
    null,
  );
});