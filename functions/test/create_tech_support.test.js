const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildTechSupportUserDoc,
  parseArgs,
  assertNoSecretFields,
  runCreateTechSupport,
  resolveProjectTarget,
  assessExistingProfile,
  assessProvisioningProfiles,
  normalizeLookupEmail,
  emailsMatch,
  shouldQueueSetupEmail,
  SETUP_MAIL_COOLDOWN_MS,
} = require("../create_tech_support");
const {SECRET_KEYS} = require("../scripts/p0-common");

/**
 * @param {{id: string, data: Record<string, unknown>}[]} profiles
 * @param {unknown[]} writers
 */
function mockUsersDb(profiles, writers = []) {
  return {
    collection: (name) => {
      if (name === "users") {
        return {
          where: (field, op, val) => ({
            limit: () => ({
              get: async () => {
                const docs = profiles.filter((p) => {
                  if (op === "in" && Array.isArray(val)) {
                    return val.includes(p.data[field]);
                  }
                  if (field === "email" && op === "==") {
                    return p.data[field] === val || normalizeLookupEmail(p.data.email) === val;
                  }
                  if (field === "emailNormalized" && op === "==") {
                    return normalizeLookupEmail(p.data.email) === val ||
                      p.data.emailNormalized === val;
                  }
                  return p.data[field] === val;
                });
                return {
                  empty: docs.length === 0,
                  docs: docs.map((p) => ({id: p.id, data: () => p.data})),
                };
              },
            }),
          }),
          doc: (id) => ({
            get: async () => {
              const p = profiles.find((x) => x.id === id);
              return {exists: !!p, data: () => p?.data};
            },
            set: async (payload, opts) => writers.push({id, payload, opts}),
          }),
        };
      }
      if (name === "mail") {
        return {add: async () => writers.push({mail: true})};
      }
      throw new Error(`unexpected collection ${name}`);
    },
  };
}

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

test("assessProvisioningProfiles blocks orphan without Auth", () => {
  const r = assessProvisioningProfiles(
    [{id: "orphan-admin", data: {role: "company-admin", companyUID: "c1"}}],
    {allowRoleChange: false, authUid: null},
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "existing_profile_scope");
});

test("assessProvisioningProfiles blocks uid mismatch", () => {
  const r = assessProvisioningProfiles(
    [{id: "orphan-admin", data: {role: "technical_support", email: "a@b.c"}}],
    {allowRoleChange: false, authUid: "auth-other"},
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "uid_mismatch");
});

test("assessProvisioningProfiles blocks uid mismatch even with allow-role-change", () => {
  const r = assessProvisioningProfiles(
    [{id: "orphan-admin", data: {role: "company-admin", companyUID: "c1", email: "a@b.c"}}],
    {allowRoleChange: true, authUid: "auth-other"},
  );
  assert.equal(r.ok, false);
  assert.equal(r.reason, "uid_mismatch");
});

test("emailsMatch is case and whitespace insensitive", () => {
  assert.ok(emailsMatch(" User@X.COM ", "user@x.com"));
  assert.ok(!emailsMatch("other@x.com", "user@x.com"));
});

test("apply refuses when stored email casing differs from CLI", async () => {
  const emailCli = "user@x.com";
  const writers = [];
  let createCalled = false;
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", "  User@X.COM ",
    "--phone", "01111111111",
    "--apply",
  ]);
  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "tashil-dev",
      db: mockUsersDb([{
        id: "orphan-admin",
        data: {
          role: "company-admin",
          companyUID: "co-9",
          email: " User@X.COM ",
          phoneNumber: "01111111111",
        },
      }], writers),
      auth: {
        getUserByEmail: async () => { throw {code: "auth/user-not-found"}; },
        createUser: async () => {
          createCalled = true;
          return {uid: "new-auth", email: emailCli};
        },
      },
    }),
    /refusing apply/,
  );
  assert.equal(createCalled, false);
  assert.equal(writers.length, 0);
});

test("apply refuses uid mismatch with allow-role-change flag", async () => {
  const email = "admin@example.com";
  const writers = [];
  let createCalled = false;
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", email,
    "--phone", "01111111111",
    "--apply",
    "--allow-role-change",
  ]);
  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "tashil-dev",
      db: mockUsersDb([{
        id: "orphan-admin",
        data: {role: "company-admin", companyUID: "co-9", email, phoneNumber: "01111111111"},
      }], writers),
      auth: {
        getUserByEmail: async () => ({uid: "auth-real"}),
        getUser: async (uid) => ({uid, email}),
        createUser: async () => {
          createCalled = true;
          return {uid: "auth-real"};
        },
      },
    }),
    /uid_mismatch|does not match Auth uid/,
  );
  assert.equal(createCalled, false);
  assert.equal(writers.length, 0);
});

test("assessExistingProfile allows technical_support refresh", () => {
  const r = assessExistingProfile({role: "tech_support", companyUID: ""}, {allowRoleChange: false});
  assert.equal(r.ok, true);
  assert.equal(r.changes.length, 0);
});

test("shouldQueueSetupEmail respects cooldown unless forced", () => {
  const recent = {lastPasswordSetupMailAt: {toMillis: () => Date.now()}};
  assert.equal(shouldQueueSetupEmail(recent, false), false);
  assert.equal(shouldQueueSetupEmail(recent, true), true);
  const old = {lastPasswordSetupMailAt: {toMillis: () => Date.now() - SETUP_MAIL_COOLDOWN_MS - 1}};
  assert.equal(shouldQueueSetupEmail(old, false), true);
});

test("dry-run requires project and empty profiles", async () => {
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", "newonly@example.com",
    "--phone", "01111111111",
  ]);
  const out = await runCreateTechSupport(args, {
    project: "tashil-dev",
    db: mockUsersDb([]),
    auth: {getUserByEmail: async () => { throw {code: "auth/user-not-found"}; }},
  });
  assert.equal(out.mode, "dry-run");
  assert.equal(out.project, "tashil-dev");
});

test("dry-run refuses existing company-admin profile", async () => {
  const email = "admin@example.com";
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", email,
    "--phone", "01111111111",
  ]);
  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "tashil-dev",
      db: mockUsersDb([{
        id: "orphan-admin",
        data: {role: "company-admin", companyUID: "c1", email, phoneNumber: "01111111111"},
      }]),
      auth: {getUserByEmail: async () => { throw {code: "auth/user-not-found"}; }},
    }),
    /refusing dry-run/,
  );
});

test("apply refuses orphan company-admin before createUser", async () => {
  const email = "orphan-admin@example.test";
  let createCalled = false;
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", email,
    "--phone", "01111111111",
    "--apply",
  ]);
  const writers = [];
  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "tashil-dev",
      db: mockUsersDb([{
        id: "orphan-admin",
        data: {role: "company-admin", companyUID: "co-9", email, phoneNumber: "01111111111"},
      }], writers),
      auth: {
        getUserByEmail: async () => { throw {code: "auth/user-not-found"}; },
        createUser: async () => {
          createCalled = true;
          return {uid: "new-auth"};
        },
      },
    }),
    /refusing apply/,
  );
  assert.equal(createCalled, false);
  assert.equal(writers.length, 0);
});

test("apply reuses auth but refuses role overwrite", async () => {
  const email = "admin@example.com";
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", email,
    "--phone", "01111111111",
    "--apply",
  ]);
  const writers = [];
  await assert.rejects(
    () => runCreateTechSupport(args, {
      project: "tashil-dev",
      db: mockUsersDb([{
        id: "uid1",
        data: {role: "company-admin", companyUID: "co-9", email, phoneNumber: "01111111111"},
      }], writers),
      auth: {
        getUserByEmail: async () => ({uid: "uid1"}),
        getUser: async (uid) => ({uid, email}),
        generatePasswordResetLink: async () => "https://example.test/reset",
      },
    }),
    /refusing apply/,
  );
  assert.equal(writers.length, 0);
});

test("apply skips duplicate setup mail within cooldown", async () => {
  const email = "tech@example.com";
  const args = parseArgs([
    "--project", "tashil-dev",
    "--email", email,
    "--phone", "01111111111",
    "--apply",
  ]);
  const writers = [];
  const auth = {
    getUserByEmail: async () => ({uid: "uid-ts"}),
    getUser: async (uid) => ({uid, email}),
    generatePasswordResetLink: async () => "https://example.test/reset",
  };
  const profiles = [{
    id: "uid-ts",
    data: {
      role: "technical_support",
      email,
      phoneNumber: "01111111111",
      lastPasswordSetupMailAt: {toMillis: () => Date.now()},
    },
  }];
  const out = await runCreateTechSupport(args, {
    project: "tashil-dev",
    db: mockUsersDb(profiles, writers),
    auth,
  });
  assert.equal(out.mailQueued, false);
  assert.equal(writers.filter((w) => w.mail).length, 0);
});

test("email and phone are required", () => {
  assert.throws(() => buildTechSupportUserDoc({uid: "u", email: "", phoneNumber: "01111111111"}));
  assert.throws(() => buildTechSupportUserDoc({uid: "u", email: "a@b.c", phoneNumber: "123"}));
  assert.throws(() => parseArgs(["--email"]));
});