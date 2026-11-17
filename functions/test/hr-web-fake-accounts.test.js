const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const lib = require("../scripts/hr-web-fake-accounts-lib");
const {main} = require("../scripts/hr-web-fake-accounts");

function memoryDb(initial = {}) {
  const docs = new Map(Object.entries(initial));
  const sets = [];
  return {
    docs,
    sets,
    async get(docPath) {
      return docs.has(docPath) ? docs.get(docPath) : null;
    },
    async set(docPath, data, opts) {
      sets.push({docPath, data});
      const prev = docs.get(docPath) || {};
      docs.set(docPath, opts && opts.merge ? {...prev, ...data} : {...data});
    },
    async delete(docPath) {
      docs.delete(docPath);
    },
  };
}

function memoryAuth(initial = {}) {
  const users = new Map(Object.entries(initial));
  const updates = [];
  return {
    users,
    updates,
    async getUser(uid) {
      return users.has(uid) ? users.get(uid) : null;
    },
    async createUser(user) {
      users.set(user.uid, {...user});
    },
    async updateUser(uid, patch) {
      updates.push({uid, patch});
      users.set(uid, {...users.get(uid), ...patch});
    },
    async deleteUser(uid) {
      users.delete(uid);
    },
  };
}

test("project guard allows only tashil-dev", () => {
  assert.equal(lib.assertDevProject("tashil-dev"), "tashil-dev");
  assert.equal(lib.assertDevProject(" Tashil-Dev "), "tashil-dev");
  assert.equal(lib.assertDevProject("projects/tashil-dev"), "tashil-dev");
  assert.equal(lib.assertCredentialProject("tashil-dev"), "tashil-dev");

  for (const project of [
    "",
    "   ",
    "practice-firebase-72df1",
    "Practice-Firebase-72df1",
    " practice-firebase-72df1 ",
    "projects/practice-firebase-72df1",
    "tashil-dev2",
    "tashil-dev.evil",
    "tashil_dev",
    "demo-hr",
    "prod",
    "production",
  ]) {
    assert.throws(() => lib.assertDevProject(project), /tashil-dev|production/, project);
    assert.throws(() => lib.assertCredentialProject(project), /tashil-dev|production/, project);
  }
  assert.throws(() => lib.assertDevProject(undefined), /required/);
  assert.throws(() => lib.assertCredentialProject(null), /required/);
});

test("parseArgs requires --project and rejects production overrides", () => {
  assert.equal(lib.parseArgs(["--project", "tashil-dev"]).project, "tashil-dev");
  assert.equal(lib.parseArgs(["--project=tashil-dev", "--apply"]).apply, true);
  assert.equal(lib.parseArgs(["--project", "tashil-dev", "--cleanup"]).cleanup, true);
  assert.equal(lib.parseArgs(["--apply"]).project, "");
  assert.throws(() => lib.assertDevProject(lib.parseArgs(["--apply"]).project), /required/);
  assert.throws(() => lib.assertDevProject(lib.parseArgs([]).project), /required/);
  assert.throws(() => lib.parseArgs(["--project", "tashil-dev", "--dry-run", "--apply"]), /dry-run/);
  assert.throws(() => lib.parseArgs(["--project", "tashil-dev", "--allow-prod-project=practice-firebase-72df1"]), /production/);
  assert.throws(() => lib.parseArgs(["--project", "tashil-dev", "--rotate-passwords"]), /rotate-passwords/);
  assert.throws(() => lib.parseArgs(["--project", "tashil-dev", "--cleanup", "--apply", "--rotate-passwords"]), /rotate-passwords/);
});

test("local credential signals refuse production without a network lookup", () => {
  assert.throws(
    () => lib.assertLocalCredentialSignals({GOOGLE_CLOUD_PROJECT: "practice-firebase-72df1"}),
    /production/,
  );
  assert.throws(
    () => lib.assertLocalCredentialSignals({GCLOUD_PROJECT: "other-project"}),
    /other-project/,
  );
  assert.throws(
    () => lib.assertLocalCredentialSignals({FIREBASE_CONFIG: JSON.stringify({projectId: "practice-firebase-72df1"})}),
    /production/,
  );
  lib.assertLocalCredentialSignals({});
  lib.assertLocalCredentialSignals({GOOGLE_CLOUD_PROJECT: "tashil-dev"});

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "hr-fake-cred-"));
  const filePath = path.join(dir, "sa.json");
  fs.writeFileSync(filePath, JSON.stringify({project_id: "practice-firebase-72df1", type: "service_account"}));
  assert.throws(
    () => lib.assertLocalCredentialSignals(
      {GOOGLE_APPLICATION_CREDENTIALS: filePath},
      (p) => fs.readFileSync(p, "utf8"),
    ),
    /production/,
  );
  fs.writeFileSync(filePath, JSON.stringify({project_id: "tashil-dev"}));
  lib.assertLocalCredentialSignals(
    {GOOGLE_APPLICATION_CREDENTIALS: filePath},
    (p) => fs.readFileSync(p, "utf8"),
  );
});

test("resolveCredentialProject reads the key file and does not call lookup", async () => {
  let lookups = 0;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "hr-fake-lookup-"));
  const filePath = path.join(dir, "sa.json");
  fs.writeFileSync(filePath, JSON.stringify({project_id: "tashil-dev"}));
  const project = await lib.resolveCredentialProject({
    env: {GOOGLE_APPLICATION_CREDENTIALS: filePath},
    readFile: (p) => fs.readFileSync(p, "utf8"),
    lookup: async () => {
      lookups += 1;
      return "practice-firebase-72df1";
    },
  });
  assert.equal(project, "tashil-dev");
  assert.equal(lookups, 0);
  await assert.rejects(
    () => lib.resolveCredentialProject({env: {}, lookup: async () => ""}),
    /could not determine/,
  );
});

test("data builder matches staff and company delegate shapes", () => {
  const plan = lib.buildPlan();
  assert.deepEqual(plan, lib.buildPlan());
  assert.equal(plan.seedTag, "tashil-dev-hr-web-fake-v1");
  assert.equal(plan.organizationId, "seed-fake-hr-org");
  assert.equal(plan.accounts.length, 32);

  const byEmail = Object.fromEntries(plan.accounts.map((account) => [account.email, account]));
  const expectAccount = (email, role, companyUID, phone, status = "approved") => {
    const account = byEmail[email];
    assert.ok(account, email);
    assert.equal(account.role, role, email);
    assert.equal(account.companyUID, companyUID, email);
    assert.equal(account.phoneNumber, phone, email);
    assert.equal(account.status, status, email);
    assert.ok(email.endsWith("@example.com"), email);
  };

  expectAccount("fake.superadmin@example.com", "super-admin", "", "01000000001");
  expectAccount("fake.techsupport@example.com", "technical_support", "", "01000000002");
  expectAccount("fake.orgadmin@example.com", "organization-admin", "", "01000000003");
  expectAccount("fake.nocompany@example.com", "hr", "seed-fake-co-alpha", "01000000004");
  expectAccount("fake.supervisor.alpha@example.com", "supervisor", "seed-fake-co-alpha", "01000000005");
  expectAccount("fake.hr.alpha@example.com", "hr", "seed-fake-co-alpha", "01000000006");
  expectAccount("fake.marketing.alpha@example.com", "marketing", "seed-fake-co-alpha", "01000000007");
  expectAccount("fake.branches-marketing.alpha@example.com", "branches_marketing", "seed-fake-co-alpha", "01000000008");
  expectAccount("fake.delegate.alpha.1@example.com", "delegate", "seed-fake-co-alpha", "01000000009", "active");
  expectAccount("fake.delegate.alpha.5@example.com", "delegate", "seed-fake-co-alpha", "01000000013", "suspended");
  expectAccount("fake.supervisor.beta@example.com", "supervisor", "seed-fake-co-beta", "01000000014");
  expectAccount("fake.hr.beta@example.com", "hr", "seed-fake-co-beta", "01000000015");
  expectAccount("fake.marketing.beta@example.com", "marketing", "seed-fake-co-beta", "01000000016");
  expectAccount("fake.branches-marketing.beta@example.com", "branches_marketing", "seed-fake-co-beta", "01000000017");
  expectAccount("fake.delegate.beta.1@example.com", "delegate", "seed-fake-co-beta", "01000000018", "active");
  expectAccount("fake.delegate.beta.5@example.com", "delegate", "seed-fake-co-beta", "01000000022", "suspended");

  for (const companyId of ["seed-fake-co-alpha", "seed-fake-co-beta"]) {
    const delegates = plan.accounts.filter((account) => account.role === "delegate" && account.companyUID === companyId);
    assert.equal(delegates.length, 5, companyId);
    assert.equal(delegates.filter((account) => account.status === "suspended").length, 1, companyId);
    assert.equal(delegates.filter((account) => account.status === "active").length, 4, companyId);
  }

  const phones = plan.accounts.map((account) => account.phoneNumber);
  assert.equal(new Set(phones).size, phones.length);
  for (const phone of phones) {
    assert.match(phone, /^01000000\d{3}$/);
    assert.notEqual(phone, "01508899965");
  }

  for (const uid of [
    "seed-fake-super-admin",
    "seed-fake-tech-support",
    "seed-fake-org-admin",
  ]) {
    const doc = plan.writes.find((write) => write.path === `users/${uid}`);
    assert.equal(Object.prototype.hasOwnProperty.call(doc.data, "companyUID"), false, uid);
    assert.equal(doc.data.organizationUID, "seed-fake-hr-org");
    assert.equal(doc.data.seedTag, plan.seedTag);
  }

  const extraHr = plan.writes.find((write) => write.path === "users/seed-fake-no-company").data;
  assert.equal(extraHr.role, "hr");
  assert.equal(extraHr.companyUID, "seed-fake-co-alpha");
  assert.equal(extraHr.companyName, "Fake Company Alpha");
  assert.equal(extraHr.email, "fake.nocompany@example.com");
  assert.equal(extraHr.displayName, "Fake HR Alpha Extra");
  assert.equal(extraHr.phoneNumber, "01000000004");

  const hrAlpha = plan.writes.find((write) => write.path === "users/seed-fake-hr-alpha").data;
  assert.equal(hrAlpha.role, "hr");
  assert.equal(hrAlpha.companyUID, "seed-fake-co-alpha");
  assert.equal(hrAlpha.email, "fake.hr.alpha@example.com");
  assert.equal(hrAlpha.phone, hrAlpha.phoneNumber);

  const nested = plan.writes.find((write) => (
    write.path === "organizations/seed-fake-hr-org/companies/seed-fake-co-beta/delegates/seed-fake-del-beta-5"
  ));
  assert.equal(nested.kind, "delegate");
  assert.equal(nested.data.status, "suspended");
  assert.equal(nested.data.companyUID, "seed-fake-co-beta");
  assert.equal(nested.data.organizationUID, "seed-fake-hr-org");
  assert.equal(nested.data.role, "delegate");
  assert.equal(nested.data.position, "Promoter");
  assert.equal(nested.data.nationalityID, "00000000000205");
  assert.equal(nested.data.nationalId, "00000000000205");
  assert.match(nested.data.nationalityID, /^[0-9]{14}$/);

  const delegateWrites = plan.writes.filter((write) => write.kind === "delegate");
  assert.equal(delegateWrites.length, 10);
  const nids = delegateWrites.map((write) => write.data.nationalityID);
  assert.equal(new Set(nids).size, nids.length);
  for (const write of delegateWrites) {
    assert.match(String(write.data.nationalityID), /^[0-9]{14}$/, write.path);
    assert.equal(write.data.nationalId, write.data.nationalityID, write.path);
  }
  assert.equal(lib.fakeNationalId("alpha", 1), "00000000000101");
  assert.equal(lib.fakeNationalId("alpha", 5), "00000000000105");
  assert.equal(lib.fakeNationalId("beta", 1), "00000000000201");

  const hrAccounts = plan.accounts.filter((account) => account.role === "hr");
  assert.equal(hrAccounts.length, 3);
  for (const account of hrAccounts) {
    assert.ok(account.companyUID, account.email);
  }
  assert.equal(nested.data.isActive, false);

  const company = plan.writes.find((write) => write.path === "organizations/seed-fake-hr-org/companies/seed-fake-co-alpha").data;
  assert.equal(company.name, "Fake Company Alpha");
  assert.equal(company.companyCodeInOrg, "FAKE-ALPHA");
  assert.equal(company.organizationUID, "seed-fake-hr-org");
  assert.equal(company.delegates, 5);

  const rootBranch = plan.writes.find((write) => write.path === "branches/seed-fake-br-alpha").data;
  const nestedBranch = plan.writes.find((write) => (
    write.path === "organizations/seed-fake-hr-org/branches/seed-fake-br-alpha"
  )).data;
  assert.equal(rootBranch.branchName, "Fake Branch Alpha");
  assert.equal(rootBranch.organizationUID, "seed-fake-hr-org");
  assert.deepEqual(rootBranch.location, nestedBranch.location);
  assert.equal(rootBranch.geofenceRadius, 100);

  const serialized = JSON.stringify(plan);
  assert.equal(serialized.includes("practice-firebase-72df1"), false);
  assert.equal(serialized.includes("\"password\""), false);
  for (const write of plan.writes) lib.assertNoSecretKeys(write.data);
});

test("the original 22 accounts keep their uids, phones and order", () => {
  const original = [
    "seed-fake-super-admin", "seed-fake-tech-support", "seed-fake-org-admin", "seed-fake-no-company",
    "seed-fake-supervisor-alpha", "seed-fake-hr-alpha", "seed-fake-marketing-alpha", "seed-fake-bmm-alpha",
    "seed-fake-del-alpha-1", "seed-fake-del-alpha-2", "seed-fake-del-alpha-3", "seed-fake-del-alpha-4",
    "seed-fake-del-alpha-5",
    "seed-fake-supervisor-beta", "seed-fake-hr-beta", "seed-fake-marketing-beta", "seed-fake-bmm-beta",
    "seed-fake-del-beta-1", "seed-fake-del-beta-2", "seed-fake-del-beta-3", "seed-fake-del-beta-4",
    "seed-fake-del-beta-5",
  ];
  const accounts = lib.buildPlan().accounts;
  original.forEach((uid, i) => {
    assert.equal(accounts[i].uid, uid);
    assert.equal(accounts[i].phoneNumber, lib.fakePhone(i + 1), uid);
  });
});

test("role-shape accounts mirror every prod supervisor / HR users doc shape", () => {
  const plan = lib.buildPlan();
  const shapes = plan.accounts.slice(22);
  assert.equal(shapes.length, lib.ROLE_SHAPE_ACCOUNTS.length);
  const doc = (uid) => plan.writes.find((write) => write.path === `users/${uid}`).data;
  const expected = [
    ["seed-fake-company-admin-invite-alpha", "company-admin", "01000000023"],
    ["seed-fake-company-admin-legacy-alpha", "company_admin", "01000000024"],
    ["seed-fake-companyadmin-companyid-alpha", "companyadmin", "01000000025"],
    ["seed-fake-admin-position-alpha", "admin", "01000000026"],
    ["seed-fake-company-supervisor-beta", "company_supervisor", "01000000027"],
    ["seed-fake-admin-usertype-hr-beta", "admin", "01000000028"],
    ["seed-fake-company-hr-alpha", "company-hr", "01000000029"],
    ["seed-fake-company-hr-beta", "company_hr", "01000000030"],
    ["seed-fake-human-resources-beta", "human_resources", "01000000031"],
    ["seed-fake-admin-no-company", "admin", "01000000032"],
  ];
  assert.deepEqual(shapes.map((a) => [a.uid, a.role, a.phoneNumber]), expected);
  for (const account of shapes) {
    assert.ok(account.email.endsWith("@example.com"), account.email);
    assert.ok(account.uid.startsWith("seed-fake-"), account.uid);
    assert.ok(account.shape, account.uid);
    const data = doc(account.uid);
    assert.equal(data.role, account.role);
    assert.equal(data.organizationUID, "seed-fake-hr-org");
    assert.equal(data.seedTag, plan.seedTag);
    assert.equal(data.fake, true);
  }

  const invite = doc("seed-fake-company-admin-invite-alpha");
  assert.equal(invite.companyUID, "seed-fake-co-alpha");
  assert.equal(invite.emailVerified, true);
  assert.equal(invite.status, "Approved");

  const legacyField = doc("seed-fake-companyadmin-companyid-alpha");
  assert.equal(legacyField.companyId, "seed-fake-co-alpha");
  assert.equal(Object.prototype.hasOwnProperty.call(legacyField, "companyUID"), false);

  assert.equal(doc("seed-fake-admin-position-alpha").position, "supervisor");
  assert.equal(doc("seed-fake-admin-usertype-hr-beta").userType, "HR");
  assert.equal(doc("seed-fake-company-supervisor-beta").companyUID, "seed-fake-co-beta");

  const noCompany = doc("seed-fake-admin-no-company");
  assert.equal(Object.prototype.hasOwnProperty.call(noCompany, "companyUID"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(noCompany, "companyId"), false);

  for (const account of plan.accounts.filter((a) => lib.HR_ROLES.has(a.role))) {
    assert.ok(account.companyUID || account.companyId, `${account.email} HR must belong to a company`);
  }
});

test("plan refuses an HR spelling without a company", () => {
  const plan = lib.buildPlan();
  const broken = plan.accounts.find((a) => a.uid === "seed-fake-company-hr-alpha");
  broken.companyUID = "";
  assert.throws(() => lib.assertPlanSafe(plan), /must belong to a company/);
});

test("dry-run text lists emails and does not contain a generated password", () => {
  const plan = lib.buildPlan();
  const password = lib.passwordFromBytes(Buffer.alloc(20, 7));
  const text = `${lib.formatDryRun(plan)}\n${lib.formatCleanupDryRun(plan)}`;
  assert.match(text, /fake.hr.beta@example.com/);
  assert.match(text, /companyadmin fake\.companyadmin\.companyid\.alpha@example\.com .*companyId=seed-fake-co-alpha/);
  assert.match(text, /mode: dry-run/);
  assert.match(text, /cleanup dry-run/);
  assert.equal(text.includes(password), false);
  assert.equal(text.includes("practice-firebase-72df1"), false);
  assert.throws(() => lib.formatApplySummary({created: 1, password: "secret"}), /secret field/);
});

test("apply is idempotent and never stores a password on a document", async () => {
  const plan = lib.buildPlan();
  const db = memoryDb();
  const auth = memoryAuth();
  let n = 0;
  const generatePassword = () => `pw-${n++}`;
  const first = await lib.applySeed({
    plan,
    db,
    auth,
    rotatePasswords: false,
    generatePassword,
    previousLedger: {accounts: []},
    serverTimestamp: () => "SERVER_TIME",
  });
  assert.equal(first.summary.created, plan.accounts.length);
  assert.equal(first.summary.unchanged, 0);
  for (const call of db.sets) {
    assert.equal(Object.prototype.hasOwnProperty.call(call.data, "password"), false);
    assert.equal(call.data.seedTag, plan.seedTag);
  }
  assert.equal(db.docs.get("users/seed-fake-hr-alpha").createdAt, "SERVER_TIME");
  assert.equal(first.ledger.accounts.find((row) => row.email === "fake.hr.alpha@example.com").password, "pw-5");

  const second = await lib.applySeed({
    plan,
    db,
    auth,
    rotatePasswords: false,
    generatePassword: () => {
      throw new Error("must not generate a password on re-run");
    },
    previousLedger: first.ledger,
    serverTimestamp: () => "SERVER_TIME_2",
  });
  assert.equal(second.summary.created, 0);
  assert.equal(second.summary.unchanged, plan.accounts.length);
  assert.equal(auth.users.get("seed-fake-hr-alpha").password, "pw-5");
  assert.equal(second.ledger.accounts.find((row) => row.email === "fake.hr.alpha@example.com").password, "pw-5");
  for (const update of auth.updates) {
    assert.equal(Object.prototype.hasOwnProperty.call(update.patch, "password"), false);
  }
  assert.equal(db.docs.get("users/seed-fake-hr-alpha").createdAt, "SERVER_TIME");

  const rotated = await lib.applySeed({
    plan,
    db,
    auth,
    rotatePasswords: true,
    generatePassword: () => "rotated-secret",
    previousLedger: second.ledger,
    serverTimestamp: () => "SERVER_TIME_3",
  });
  assert.equal(rotated.summary.rotated, plan.accounts.length);
  assert.equal(auth.users.get("seed-fake-super-admin").password, "rotated-secret");
  assert.equal(db.docs.get("users/seed-fake-super-admin").password, undefined);

  const blocked = memoryAuth();
  blocked.users.set("other-uid", {email: "fake.superadmin@example.com"});
  const freshDb = memoryDb();
  await assert.rejects(
    () => lib.applySeed({
      plan,
      db: freshDb,
      auth: {
        async getUser() {
          return null;
        },
        async createUser() {
          const error = new Error("The email address is already in use by another account.");
          error.code = "auth/email-already-exists";
          throw error;
        },
        async updateUser() {
          throw new Error("should not update a foreign auth user");
        },
      },
      rotatePasswords: false,
      generatePassword: () => "must-not-leak",
      previousLedger: {accounts: []},
      serverTimestamp: () => "T",
    }),
    /refusing to touch it/,
  );
  assert.equal(JSON.stringify(freshDb.docs.get("users/seed-fake-super-admin")).includes("must-not-leak"), false);
});

test("cleanup deletes only tagged fake docs and matching example.com auth users", async () => {
  const plan = lib.buildPlan();
  const db = memoryDb();
  const auth = memoryAuth();
  await lib.applySeed({
    plan,
    db,
    auth,
    rotatePasswords: false,
    generatePassword: () => "pw",
    previousLedger: {accounts: []},
    serverTimestamp: () => "T",
  });
  db.docs.set("users/real-person", {
    email: "real.person@company.test",
    role: "hr",
    companyUID: "seed-fake-co-alpha",
  });
  db.docs.set("users/seed-fake-tech-support", {
    ...db.docs.get("users/seed-fake-tech-support"),
    seedTag: "someone-else",
    fake: false,
  });
  db.docs.set("users/seed-fake-hr-beta", {
    ...db.docs.get("users/seed-fake-hr-beta"),
    email: "real.hr@company.test",
  });
  auth.users.set("seed-fake-hr-beta", {email: "real.hr@company.test"});
  db.docs.delete("users/seed-fake-super-admin");

  const report = await lib.cleanupSeed({plan, db, auth});
  assert.equal(db.docs.has("users/real-person"), true);
  assert.equal(db.docs.has("users/seed-fake-tech-support"), true);
  assert.equal(auth.users.has("seed-fake-tech-support"), true);
  assert.equal(auth.users.has("seed-fake-hr-beta"), true);
  assert.equal(db.docs.has("users/seed-fake-hr-beta"), true);
  assert.equal(db.docs.has("users/seed-fake-super-admin"), false);
  assert.equal(auth.users.has("seed-fake-super-admin"), false);
  assert.equal(db.docs.has("organizations/seed-fake-hr-org"), false);
  assert.equal(db.docs.has("users/seed-fake-hr-alpha"), false);
  assert.ok(report.deletedAuth.includes("fake.superadmin@example.com"));
  assert.equal(report.deletedAuth.includes("fake.techsupport@example.com"), false);
  assert.equal(report.deletedAuth.includes("fake.hr.beta@example.com"), false);
  assert.ok(report.skippedDocs.some((row) => row.path === "users/seed-fake-tech-support" && row.reason === "not-tagged"));
  assert.ok(report.skippedDocs.some((row) => row.path === "users/seed-fake-hr-beta" && row.reason === "email-diverged"));
});

test("password ledger path is the gitignored local file and keeps prior secrets", () => {
  assert.throws(() => lib.assertPasswordFilePath("/tmp/passwords.json"), /local\.json/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "hr-fake-ledger-"));
  const filePath = path.join(dir, lib.PASSWORD_FILE_NAME);
  const ledger = lib.mergePasswordLedger({accounts: []}, [
    {email: "fake.hr.alpha@example.com", uid: "seed-fake-hr-alpha", role: "hr", phoneNumber: "01000000006", status: "created", password: "kept-secret"},
  ]);
  lib.writePasswordLedger(filePath, ledger);
  assert.equal(fs.statSync(filePath).mode & 0o777, 0o600);
  const merged = lib.mergePasswordLedger(lib.readPasswordLedger(filePath), [
    {email: "fake.hr.alpha@example.com", uid: "seed-fake-hr-alpha", role: "hr", phoneNumber: "01000000006", status: "unchanged"},
  ]);
  assert.equal(merged.accounts[0].password, "kept-secret");
  assert.equal(merged.project, "tashil-dev");
  const gitignore = fs.readFileSync(path.join(__dirname, "../../.gitignore"), "utf8");
  assert.match(gitignore, /\.hr-web-fake-accounts\.local\.json/);
});

test("cli dry-run prints the plan and apply refuses foreign credentials before initialization", async () => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(String(line));
  try {
    const dry = await main(["--project", "tashil-dev"], {});
    assert.equal(dry.mode, "dry-run");
    const cleanup = await main(["--project=tashil-dev", "--cleanup"], {});
    assert.equal(cleanup.mode, "cleanup-dry-run");
  } finally {
    console.log = original;
  }
  const printed = logs.join("\n");
  assert.match(printed, /fake\.superadmin@example\.com/);
  assert.match(printed, /fake\.delegate\.beta\.5@example\.com/);
  assert.equal(printed.includes("practice-firebase-72df1"), false);

  let initialized = false;
  await assert.rejects(
    () => main(["--project", "tashil-dev", "--apply"], {}, {
      lookupCredentialProject: async () => "practice-firebase-72df1",
      admin: {initializeApp() { initialized = true; }},
    }),
    /production/,
  );
  assert.equal(initialized, false);

  await assert.rejects(
    () => main(["--project", "practice-firebase-72df1"], {}),
    /production/,
  );
  await assert.rejects(
    () => main(["--project", "tashil-dev"], {GOOGLE_CLOUD_PROJECT: "practice-firebase-72df1"}),
    /production/,
  );
});

test("readme lists every fake account email", () => {
  const readme = fs.readFileSync(path.join(__dirname, "../../README.md"), "utf8");
  const scriptReadme = fs.readFileSync(
    path.join(__dirname, "../scripts/README-hr-web-fake-accounts.md"),
    "utf8",
  );
  for (const account of lib.publicCatalog()) {
    const pattern = new RegExp(account.email.replace(/\./g, "\\."));
    assert.match(readme, pattern, account.email);
    assert.match(scriptReadme, pattern, account.email);
  }
  assert.match(readme, /tashil-dev/);
  assert.match(scriptReadme, /practice-firebase-72df1/);
});
