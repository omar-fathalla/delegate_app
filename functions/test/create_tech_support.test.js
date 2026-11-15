const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildTechSupportUserDoc,
  parseArgs,
  assertNoSecretFields,
  runCreateTechSupport,
  resolveProjectTarget,
  assessExistingProfile,
  shouldQueueSetupEmail,
  SETUP_MAIL_COOLDOWN_MS,
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

test("project allow-list and prod refusal", () => {
  assert.equal(resolveProjectTarget({project: "tashil-dev", allowProd: ""}), "tashil-dev");
  assert.throws(
    () => resolveProjectTarget({project: "practice-firebase-72df1", allowProd: ""}),
    /allow-list/,
  );
  assert.throws(() => resolveProjectTarget({project: "", allowProd: ""}), /--project/);
});

test("assessExistingProfile blocks company-admin without allow-role-change", () => {
  const r = assessExistingProfile({role: "company-admin", companyUID: "co-1"}, {allowRoleChange: false});
  assert.equal(r.ok, false);
  assert.equal(r.reason, "existing_profile_scope");
  assert.ok(r.changes.some((c) => c.field === "role"));
  assert.ok(r.changes.some((c) => c.field === "companyUID"));
});

test("assessExistingProfile allows technical_support refresh", () => {
  const r = assessExistingProfile({role: "tech_support", companyUID: ""}, {allowRoleChange: false});
  assert.equal(r.ok, true);
  assert.equal(r.changes.length, 0);
});

test("assessExistingProfile allows scope change with flag", () => {
  const r = assessExistingProfile({role: "company-admin", companyUID: "co-1"}, {allowRoleChange: true});
  assert.equal(r.ok, true);
  assert.ok(r.changes.length >= 1);
});

test("shouldQueueSetupEmail respects cooldown unless forced", () => {
  const recent = {lastPasswordSetupMailAt: {toMillis: () => Date.now()}};
  assert.equal(shouldQueueSetupEmail(recent, false), false);
  assert.equal(shouldQueueSetupEmail(recent, true), true);
  const old = {lastPasswordSetupMailAt: {toMillis: () => Date.now() - SETUP_MAIL_COOLDOWN_MS - 1}};
  assert.equal(shouldQueueSetupEmail(old, false), true);
});

test("dry-run requires project and prints target (no Firestore)", async () => {
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", "newonly@example.com",
    "--phone", "01111111111",
  ]);
  assert.equal(args.apply, false);
  const out = await runCreateTechSupport(args, {project: "tashil-dev"});
  assert.equal(out.mode, "dry-run");
  assert.equal(out.project, "tashil-dev");
});

test("dry-run refuses existing company-admin profile", async () => {
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", "admin@example.com",
    "--phone", "01111111111",
  ]);
  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "tashil-dev",
      db: {
        collection: () => ({
          where: () => ({
            limit: () => ({
              get: async () => ({
                empty: false,
                docs: [{id: "uid1", data: () => ({role: "company-admin", companyUID: "c1"})}],
              }),
            }),
          }),
        }),
      },
    }),
    /existing profile/,
  );
});

test("apply reuses auth but refuses role overwrite", async () => {
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", "admin@example.com",
    "--phone", "01111111111",
    "--apply",
  ]);
  const writes = [];
  const auth = {
    createUser: async () => {
      const e = new Error("exists");
      e.code = "auth/email-already-exists";
      throw e;
    },
    getUserByEmail: async () => ({uid: "uid1"}),
    generatePasswordResetLink: async () => "https://example.test/reset",
  };
  const db = {
    collection: (name) => {
      if (name === "users") {
        return {
          doc: (id) => ({
            get: async () => ({
              exists: true,
              data: () => ({role: "company-admin", companyUID: "co-9"}),
            }),
            set: async (payload, opts) => writes.push({id, payload, opts}),
          }),
          where: () => ({
            limit: () => ({get: async () => ({empty: true, docs: []})}),
          }),
        };
      }
      if (name === "mail") {
        return {add: async () => writes.push({mail: true})};
      }
      throw new Error("unexpected collection");
    },
  };
  await assert.rejects(
    () => runCreateTechSupport(args, {project: "tashil-dev", db, auth}),
    /existing profile/,
  );
  assert.equal(writes.length, 0);
});

test("apply skips duplicate setup mail within cooldown", async () => {
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", "tech@example.com",
    "--phone", "01111111111",
    "--apply",
  ]);
  let mailAdds = 0;
  const auth = {
    createUser: async () => ({uid: "uid-ts"}),
    generatePasswordResetLink: async () => "https://example.test/reset",
  };
  const db = {
    collection: (name) => {
      if (name === "users") {
        return {
          doc: () => ({
            get: async () => ({
              exists: true,
              data: () => ({
                role: "technical_support",
                lastPasswordSetupMailAt: {toMillis: () => Date.now()},
              }),
            }),
            set: async () => undefined,
          }),
          where: () => ({
            limit: () => ({get: async () => ({empty: true, docs: []})}),
          }),
        };
      }
      if (name === "mail") {
        return {add: async () => { mailAdds++; }};
      }
      throw new Error("unexpected");
    },
  };
  const out = await runCreateTechSupport(args, {project: "tashil-dev", db, auth});
  assert.equal(out.mailQueued, false);
  assert.equal(mailAdds, 0);
});

test("email and phone are required", () => {
  assert.throws(() => buildTechSupportUserDoc({uid: "u", email: "", phoneNumber: "01111111111"}));
  assert.throws(() => buildTechSupportUserDoc({uid: "u", email: "a@b.c", phoneNumber: "123"}));
  assert.throws(() => parseArgs(["--email"]));
});