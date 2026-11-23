/**
 * TAS-73 (photos): the app's photo_permissions / captured_photos lists carry
 * the tenant filter the rules need, so every role in the app is allowed and
 * sees only its own company or organization. The shapes here mirror
 * photo_permission_remote_datasource.dart and the marketing home screens.
 * Fake data only.
 *
 * npm run test:rules:tas73-photos
 */
const {describe, test, before, after} = require("node:test");
const assert = require("node:assert");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {
  doc, setDoc, getDocs, collection, collectionGroup, query, where,
} = require("firebase/firestore");

const ORG_A = "seed-fake-tas73-org-a";
const ORG_B = "seed-fake-tas73-org-b";
const CO_A1 = "seed-fake-tas73-co-a1";
const CO_A2 = "seed-fake-tas73-co-a2";
const CO_B1 = "seed-fake-tas73-co-b1";
const COMPANIES = [[ORG_A, CO_A1], [ORG_A, CO_A2], [ORG_B, CO_B1]];

const staff = {
  "orgadmin-a": {role: "organization-admin", organizationUID: ORG_A},
  "mktpromo-a": {role: "marketing_promotion", organizationUID: ORG_A},
  "mktpromo-a1": {role: "marketing_promotion", organizationUID: ORG_A, companyUID: CO_A1},
  "bm-a1": {role: "branches_marketing", organizationUID: ORG_A, companyUID: CO_A1},
  "sup-a1": {role: "supervisor", organizationUID: ORG_A, companyUID: CO_A1},
  "hr-a1": {role: "hr", organizationUID: ORG_A, companyUID: CO_A1},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas73-photos",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    for (const [org, co] of COMPANIES) {
      await setDoc(doc(db, `organizations/${org}/companies/${co}`), {name: co, fake: true});
      const perm = `organizations/${org}/companies/${co}/photo_permissions/perm-${co}`;
      await setDoc(doc(db, perm), {
        companyUID: co, organizationUID: org, status: "pending", fake: true,
      });
      await setDoc(doc(db, `${perm}/captured_photos/photo-${co}`), {
        companyUID: co, organizationUID: org, delegateUID: `del-${co}`,
        branchName: "fake-branch", fake: true,
      });
    }
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const delegateDb = (delegateId, orgId, companyId, extra = {}) => env.authenticatedContext(delegateId, {
  role: "delegate", delegateId, delegateIds: [delegateId], orgId, companyId, ...extra,
}).firestore();

// Mirrors _tenantQuery in photo_permission_remote_datasource.dart.
const tenantQuery = (db, group, {companyUID = "", organizationUID = ""}) => {
  const base = collectionGroup(db, group);
  if (companyUID) return query(base, where("companyUID", "==", companyUID));
  if (organizationUID) return query(base, where("organizationUID", "==", organizationUID));
  return base;
};

const companies = (snap) => snap.docs.map((d) => d.data().companyUID).sort();

describe("photo_permissions tenant lists (marketing home screens, getPermissions)", () => {
  test("org-scoped marketing_promotion lists its organization only", async () => {
    const u = staff["mktpromo-a"];
    const snap = await assertSucceeds(getDocs(tenantQuery(as("mktpromo-a"), "photo_permissions", u)));
    assert.deepStrictEqual(companies(snap), [CO_A1, CO_A2].sort());
  });

  test("company-bound marketing_promotion lists its company only", async () => {
    const u = staff["mktpromo-a1"];
    const snap = await assertSucceeds(getDocs(tenantQuery(as("mktpromo-a1"), "photo_permissions", u)));
    assert.deepStrictEqual(companies(snap), [CO_A1]);
  });

  test("branches_marketing lists its company only", async () => {
    const u = staff["bm-a1"];
    const snap = await assertSucceeds(getDocs(tenantQuery(as("bm-a1"), "photo_permissions", u)));
    assert.deepStrictEqual(companies(snap), [CO_A1]);
  });

  test("org-admin lists its organization", async () => {
    const u = staff["orgadmin-a"];
    const snap = await assertSucceeds(getDocs(tenantQuery(as("orgadmin-a"), "photo_permissions", u)));
    assert.deepStrictEqual(companies(snap), [CO_A1, CO_A2].sort());
  });
});

describe("photo_permissions ongoing list for delegates (getOngoingPermissions)", () => {
  const ongoing = (db, org) => getDocs(query(
    collectionGroup(db, "photo_permissions"), where("organizationUID", "==", org),
  ));

  test("a delegate lists its primary chain", async () => {
    const snap = await assertSucceeds(ongoing(delegateDb("del-1", ORG_A, CO_A1), ORG_A));
    assert.strictEqual(snap.size, 2);
  });

  // TAS-215: a delegate in two chains gets orgIds/companyIds claims from
  // delegateLoginV2 (buildCustomClaimsForProfiles). Its second chain's ongoing
  // permissions must list; a chain outside orgIds stays denied.
  test("a multi-chain delegate lists its second chain (orgIds claim)", async () => {
    const db = delegateDb("del-multi", ORG_A, CO_A1, {orgIds: [ORG_A, ORG_B], companyIds: [CO_A1, CO_B1]});
    const snap = await assertSucceeds(ongoing(db, ORG_B));
    assert.strictEqual(snap.size, 1);
  });

  test("a single-chain delegate cannot list another chain", () =>
    assertFails(ongoing(delegateDb("del-1", ORG_A, CO_A1), ORG_B)));

  // Supervisors sign in through delegateLoginV2, so their token says
  // role "delegate"; the company list must still pass through companyScoped().
  test("a supervisor with a delegate token lists its company (getPermissions)", async () => {
    const db = delegateDb("sup-del-1", ORG_A, CO_A1);
    const snap = await assertSucceeds(getDocs(
      tenantQuery(db, "photo_permissions", {companyUID: CO_A1, organizationUID: ORG_A}),
    ));
    assert.deepStrictEqual(companies(snap), [CO_A1]);
  });
});

describe("captured_photos lists", () => {
  test("nested list of one permission with company + organization filter (getCapturedPhotos)", async () => {
    for (const uid of ["sup-a1", "hr-a1", "orgadmin-a", "mktpromo-a"]) {
      const q = query(
        collection(as(uid), `organizations/${ORG_A}/companies/${CO_A1}/photo_permissions/perm-${CO_A1}/captured_photos`),
        where("companyUID", "==", CO_A1),
        where("organizationUID", "==", ORG_A),
      );
      const snap = await assertSucceeds(getDocs(q));
      assert.deepStrictEqual(companies(snap), [CO_A1], uid);
    }
  });

  test("a delegate lists the photos of a permission in its chain", async () => {
    const q = query(
      collection(delegateDb("del-3", ORG_A, CO_A1), `organizations/${ORG_A}/companies/${CO_A1}/photo_permissions/perm-${CO_A1}/captured_photos`),
      where("companyUID", "==", CO_A1),
      where("organizationUID", "==", ORG_A),
    );
    await assertSucceeds(getDocs(q));
  });

  test("org-admin (no companyUID) lists its organization's photos (getCompanyCapturedPhotos)", async () => {
    const snap = await assertSucceeds(getDocs(tenantQuery(as("orgadmin-a"), "captured_photos", staff["orgadmin-a"])));
    assert.deepStrictEqual(companies(snap), [CO_A1, CO_A2].sort());
  });

  test("company staff list their company's photos", async () => {
    const snap = await assertSucceeds(getDocs(tenantQuery(as("hr-a1"), "captured_photos", staff["hr-a1"])));
    assert.deepStrictEqual(companies(snap), [CO_A1]);
  });

  test("a delegate lists its own photos by delegateUID (getDelegateCapturedPhotos)", async () => {
    const db = delegateDb(`del-${CO_A1}`, ORG_A, CO_A1);
    const snap = await assertSucceeds(getDocs(query(
      collectionGroup(db, "captured_photos"), where("delegateUID", "==", `del-${CO_A1}`),
    )));
    assert.deepStrictEqual(companies(snap), [CO_A1]);
  });
});
