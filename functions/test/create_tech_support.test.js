const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildTechSupportUserDoc,
  parseArgs,
  assertNoSecretFields,
  runCreateTechSupport,
} = require("../create_tech_support");
const {SECRET_KEYS} = require("../scripts/p0-common");

test("tech support doc uses uid and stores no password fields", () => {
  const doc = buildTechSupportUserDoc({
    uid: "auth-uid",
    email: "tech@example.com",
    phoneNumber: "01111111111",
  });
  assert.equal(doc.uid, "auth-uid");
  assert.equal(doc.email, "tech@example.com");
  assert.equal(doc.role, "technical_support");
  for (const k of SECRET_KEYS) {
    assert.equal(Object.prototype.hasOwnProperty.call(doc, k), false);
  }
});

test("assertNoSecretFields rejects forbidden keys", () => {
  assert.throws(() => assertNoSecretFields({password: "x"}), /forbidden/);
});

test("cli args and default dry-run", async () => {
  const args = parseArgs([
    "--email", "tech@switchpoint.com",
    "--phone", "01111111111",
  ]);
  assert.equal(args.apply, false);
  const out = await runCreateTechSupport(args);
  assert.equal(out.mode, "dry-run");
});

test("email and phone are required", () => {
  assert.throws(() => buildTechSupportUserDoc({uid: "u", email: "", phoneNumber: "01111111111"}));
  assert.throws(() => buildTechSupportUserDoc({uid: "u", email: "a@b.c", phoneNumber: "123"}));
  assert.throws(() => parseArgs(["--email"]));
});