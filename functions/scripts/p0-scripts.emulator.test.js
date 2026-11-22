/**
 * Emulator test for the P0 scripts (purge, revoke+reset, role counts).
 *   firebase emulators:exec --only auth,firestore --project demo-p0-scripts \
 *     "node --test functions/scripts/p0-scripts.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const common = require("./p0-common");
const {purge} = require("./purge-password-fields");
const {run} = require("./revoke-and-force-reset");
const {counts} = require("./role-counts");
const usersCompany = require("./backfill-delegate-users-company");
const penaltyOrg = require("./backfill-penalty-organization-id");
const delegateCreatedAt = require("./backfill-delegate-created-at");

const live = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

test("guards: allow-list, normalized; prod and look-alikes refused", () => {
  const t = (...a) => common.assertTarget(common.parseArgs(a));
  assert.throws(() => t(), /required/);
  for (const p of ["practice-firebase-72df1", "Practice-Firebase-72df1", " practice-firebase-72df1 ",
    "projects/practice-firebase-72df1", "123456789012", "tashil-prod", "tashil-dev2", "demo-", "other"]) {
    assert.throws(() => t("--project", p, "--apply"), /allow-list|required/, p);
  }
  assert.equal(t("--project=tashil-dev"), "tashil-dev");
  assert.equal(t("--project", " Tashil-Dev "), "tashil-dev");
  assert.equal(t("--project", "projects/tashil-dev"), "tashil-dev");
  assert.equal(t("--project", "demo-p0-scripts"), "demo-p0-scripts");
  assert.throws(() => t("--project", "practice-firebase-72df1", "--allow-prod-project=tashil-dev"), /allow-list/);
  assert.equal(t("--project", "practice-firebase-72df1", "--allow-prod-project=practice-firebase-72df1"), "practice-firebase-72df1");
  assert.equal(common.resetPriority("super_admin"), 0);
  assert.equal(common.resetPriority("hr"), 1);
  assert.equal(common.resetPriority("delegate"), -1);
});

test("purge, revoke+reset and role counts on emulators", {skip: !live}, async () => {
  admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-p0-scripts"});
  const db = admin.firestore(); const auth = admin.auth();
  await auth.createUser({uid: "sa", email: "sa@e.test"});
  await auth.createUser({uid: "hr", email: "hr@e.test"});
  await db.doc("users/sa").set({role: "super-admin", email: "sa@e.test", password: "x"});
  await db.doc("users/hr").set({role: "hr", email: "hr@e.test", temporaryPassword: "y"});
  await db.doc("users/d1").set({role: "delegate", phoneNumber: "010"});

  const dry = await purge(db, false);
  assert.equal(dry.withSecret, 2); assert.equal(dry.updated, 0);
  assert.equal((await db.doc("users/sa").get()).get("password"), "x");
  const ap = await purge(db, true);
  assert.equal(ap.updated, 2);
  assert.equal((await purge(db, false)).withSecret, 0);

  const before = (await auth.getUser("sa")).tokensValidAfterTime;
  const dr = await run(db, auth, {apply: false, superOnly: false});
  assert.deepEqual([dr.targets, dr.superAdmins, dr.revoked], [2, 1, 0]);
  const so = await run(db, auth, {apply: true, superOnly: true});
  assert.deepEqual([so.targets, so.revoked, so.resetQueued], [1, 1, 1]);
  assert.notEqual((await auth.getUser("sa")).tokensValidAfterTime, before);
  assert.equal((await db.doc("users/hr").get()).get("requireReLogin"), undefined);
  assert.equal((await db.collection("mail").get()).size, 1);

  assert.deepEqual(await counts(db), {total: 3, byRole: {"super-admin": 1, "hr": 1, "delegate": 1}});
  await Promise.all(admin.apps.map((a) => a && a.delete()));
});

// TAS-224: penalty organizationId backfill.
test("penalty org resolution: branch first, unique company, never a guess", () => {
  const {resolvePenaltyOrg: r} = penaltyOrg;
  const branchOrg = new Map([["b1", "oA"], ["bX", "oX"]]);
  const companyOrgs = new Map([["c1", new Set(["oA"])], ["cMulti", new Set(["oA", "oB"])]]);
  assert.deepEqual(r({organizationId: "oZ"}, branchOrg, companyOrgs), {org: "", how: "hasOrg"});
  assert.deepEqual(r({branchId: "b1", companyId: "cMulti"}, branchOrg, companyOrgs), {org: "oA", how: "byBranch"});
  assert.deepEqual(r({companyId: "c1"}, branchOrg, companyOrgs), {org: "oA", how: "byUniqueCompany"});
  assert.deepEqual(r({companyId: "cMulti"}, branchOrg, companyOrgs), {org: "", how: "ambiguousCompany"});
  assert.deepEqual(r({branchId: "bX", companyId: "c1"}, branchOrg, companyOrgs), {org: "", how: "branchCompanyMismatch"});
  assert.deepEqual(r({companyId: "nowhere"}, branchOrg, companyOrgs), {org: "", how: "unresolved"});
});

test("penalty org backfill on the emulator: dry run writes nothing, apply fills only the gap", {skip: !live}, async () => {
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-p0-scripts"});
  const db = admin.firestore();
  await db.doc("organizations/oA/companies/c1").set({name: "fake"});
  await db.doc("organizations/oA/companies/cM").set({name: "fake"});
  await db.doc("organizations/oB/companies/cM").set({name: "fake"});
  await db.doc("branches/b1").set({organizationUID: "oB", companyUID: "cM"});
  await db.doc("penalties/p-unique").set({companyId: "c1", title: "fake"});
  await db.doc("penalties/p-branch").set({companyId: "cM", branchId: "b1", title: "fake"});
  await db.doc("penalties/p-ambig").set({companyId: "cM", title: "fake"});
  await db.doc("penalties/p-has").set({companyId: "c1", organizationId: "oKeep", title: "fake"});

  const dry = await penaltyOrg.backfill(db, false);
  assert.equal(dry.updated, 0);
  assert.equal((await db.doc("penalties/p-unique").get()).get("organizationId"), undefined);

  const run = await penaltyOrg.backfill(db, true);
  assert.equal(run.updated, 2);
  assert.equal(run.ambiguousCompany, 1);
  assert.equal((await db.doc("penalties/p-unique").get()).get("organizationId"), "oA");
  assert.equal((await db.doc("penalties/p-branch").get()).get("organizationId"), "oB");
  assert.equal((await db.doc("penalties/p-ambig").get()).get("organizationId"), undefined);
  assert.equal((await db.doc("penalties/p-has").get()).get("organizationId"), "oKeep");
  assert.equal((await db.doc("penalties/p-unique").get()).get("title"), "fake");

  const again = await penaltyOrg.backfill(db, true);
  assert.equal(again.updated, 0, "second run is a no-op");
});

// TAS-225: companyUID backfill on delegate users docs.
test("users company resolution: one company only, field roles only", () => {
  const {resolveUserCompany: r} = usersCompany;
  const one = {companies: new Set(["c1"]), orgs: new Set(["oA"])};
  const twoOrgs = {companies: new Set(["c1"]), orgs: new Set(["oA", "oB"])};
  const twoCos = {companies: new Set(["c1", "c2"]), orgs: new Set(["oA"])};
  assert.deepEqual(r({role: "hr"}, one), {how: "notDelegate", patch: {}});
  assert.deepEqual(r({role: "delegate", companyUID: "cX"}, one), {how: "hasCompany", patch: {}});
  assert.deepEqual(r({role: "delegate"}, one), {how: "filled", patch: {companyUID: "c1", organizationUID: "oA"}});
  assert.deepEqual(r({role: "Promoter", organizationUID: "oZ"}, one), {how: "filled", patch: {companyUID: "c1"}});
  assert.deepEqual(r({role: "delegate"}, twoOrgs), {how: "filled", patch: {companyUID: "c1"}});
  assert.deepEqual(r({role: "delegate"}, twoCos), {how: "severalCompanies", patch: {}});
  assert.deepEqual(r({role: "delegate"}, undefined), {how: "noDelegateDoc", patch: {}});
});

test("users company backfill on the emulator: dry run writes nothing, apply fills only the gap", {skip: !live}, async () => {
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-p0-scripts"});
  const db = admin.firestore();
  await db.doc("organizations/oA/companies/c1/delegates/u-fill").set({fullName: "fake"});
  await db.doc("organizations/oA/companies/c1/delegates/u-multi").set({fullName: "fake"});
  await db.doc("organizations/oA/companies/c2/delegates/u-multi").set({fullName: "fake"});
  await db.doc("users/u-fill").set({role: "delegate", phoneNumber: "0100000000x"});
  await db.doc("users/u-multi").set({role: "delegate"});
  await db.doc("users/u-keep").set({role: "delegate", companyUID: "cKeep"});
  await db.doc("users/u-orphan").set({role: "promoter"});
  await db.doc("users/u-staff").set({role: "hr"});

  const dry = await usersCompany.backfill(db, false);
  assert.equal(dry.updated, 0);
  assert.equal((await db.doc("users/u-fill").get()).get("companyUID"), undefined);

  const run = await usersCompany.backfill(db, true);
  assert.equal(run.updated, 1);
  assert.equal(run.severalCompanies, 1);
  assert.ok(run.noDelegateDoc >= 1, "u-orphan (and earlier tests' users) have no delegate doc");
  const filled = (await db.doc("users/u-fill").get()).data();
  assert.equal(filled.companyUID, "c1");
  assert.equal(filled.organizationUID, "oA");
  assert.equal(filled.phoneNumber, "0100000000x");
  assert.equal((await db.doc("users/u-multi").get()).get("companyUID"), undefined);
  assert.equal((await db.doc("users/u-keep").get()).get("companyUID"), "cKeep");
  assert.equal((await db.doc("users/u-staff").get()).get("companyUID"), undefined);
  assert.equal((await usersCompany.backfill(db, true)).updated, 0, "second run is a no-op");
});

// TAS-230: server createdAt for nested delegates with no start date.
test("delegate date classification: only docs with no date get createdAt", () => {
  const {classifyDelegateDate: c, needsCreatedAt: n} = delegateCreatedAt;
  assert.equal(c({createdAt: "x"}), "hasCreatedAt");
  assert.equal(c({hiredAt: "x"}), "hasOtherDate");
  assert.equal(c({subscription: {startDate: "x"}}), "hasOtherDate");
  assert.equal(c({documents: [{uploadedAt: "2026-01-02"}]}), "fromUploadedAt");
  assert.equal(c({documents: []}), "noDate");
  assert.equal(c({}), "noDate");
  assert.deepEqual(["hasCreatedAt", "hasOtherDate", "fromUploadedAt", "noDate"].map(n), [false, false, true, true]);
});

test("delegate createdAt backfill on the emulator: dry run writes nothing, apply uses createTime", {skip: !live}, async () => {
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-p0-scripts"});
  const db = admin.firestore();
  const base = "organizations/oD/companies/cD/delegates";
  await db.doc(`${base}/d-none`).set({fullName: "fake"});
  await db.doc(`${base}/d-upload`).set({fullName: "fake", documents: [{uploadedAt: "2020-01-01T00:00:00.000"}]});
  const keep = admin.firestore.Timestamp.fromDate(new Date("2024-05-05T00:00:00Z"));
  await db.doc(`${base}/d-keep`).set({fullName: "fake", createdAt: keep});
  await db.doc(`${base}/d-hired`).set({fullName: "fake", hiredAt: "2024-01-01"});
  await db.doc("delegates/top-level").set({fullName: "fake"});

  const dry = await delegateCreatedAt.backfill(db, false);
  assert.equal(dry.updated, 0);
  assert.equal((await db.doc(`${base}/d-none`).get()).get("createdAt"), undefined);

  const run = await delegateCreatedAt.backfill(db, true);
  // Earlier tests leave undated delegate docs in the same emulator: the
  // apply writes exactly what the dry run counted.
  assert.ok(dry.noDate >= 1 && dry.fromUploadedAt >= 1);
  assert.equal(run.updated, dry.noDate + dry.fromUploadedAt);
  const none = await db.doc(`${base}/d-none`).get();
  assert.ok(none.get("createdAt") instanceof admin.firestore.Timestamp);
  assert.equal(none.get("createdAt").toMillis(), none.createTime.toMillis());
  assert.ok((await db.doc(`${base}/d-upload`).get()).get("createdAt") instanceof admin.firestore.Timestamp);
  assert.equal((await db.doc(`${base}/d-keep`).get()).get("createdAt").toMillis(), keep.toMillis());
  assert.equal((await db.doc(`${base}/d-hired`).get()).get("createdAt"), undefined);
  assert.equal((await db.doc("delegates/top-level").get()).get("createdAt"), undefined);
  assert.equal((await delegateCreatedAt.backfill(db, true)).updated, 0, "second run is a no-op");
});
