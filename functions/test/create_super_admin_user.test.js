const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildSuperAdminUserDoc,
  docFromArgs,
  parseArgs,
} = require("../scripts/create-super-admin-user");

test("super-admin doc uses the supplied uid and email and stores no password", () => {
  const doc = buildSuperAdminUserDoc({
    uid: "auth-uid",
    email: "person@example.com",
    organizationUID: "org-1",
    organizationName: "Org",
    companyUID: "comp-1",
    companyName: "Company",
  });

  assert.equal(doc.uid, "auth-uid");
  assert.equal(doc.email, "person@example.com");
  assert.equal(doc.phoneNumber, "01508899965");
  assert.equal(doc.role, "super-admin");
  assert.equal(doc.displayName, "Omar Fathalla");
  assert.equal(doc.organizationUID, "org-1");
  assert.equal(doc.companyUID, "comp-1");
  assert.equal(Object.prototype.hasOwnProperty.call(doc, "password"), false);
  assert.equal(JSON.stringify(doc).includes("icloud.com"), false);
});

test("cli args map onto the same document and stay dry-run by default", () => {
  const args = parseArgs([
    "--uid", "auth-uid",
    "--email", "other@example.com",
    "--organization-uid", "org-9",
    "--organization-name", "Market",
  ]);
  assert.equal(args.apply, false);
  const {uid, doc} = docFromArgs(args);
  assert.equal(uid, "auth-uid");
  assert.equal(doc.email, "other@example.com");
  assert.equal(doc.role, "super-admin");
  assert.equal(doc.organizationUID, "org-9");
  assert.equal(doc.organizationName, "Market");
});

test("uid and email are required", () => {
  assert.throws(() => buildSuperAdminUserDoc({uid: "", email: "a@b.c"}));
  assert.throws(() => buildSuperAdminUserDoc({uid: "uid", email: ""}));
  assert.throws(() => parseArgs(["--uid"]));
});
