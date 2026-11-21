/**
 * P0 users-write hardening (FIX_PLAN_USERS_WRITE rev 3.2).
 * Emulator only (project demo-tashil-p0). Delegate login rules are not
 * changed by P0; the delegate rows here are regression checks.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment, assertFails, assertSucceeds,
} = require("./_rules_testing");
const {Timestamp} = require("firebase/firestore");

const PROJECT_ID = "demo-tashil-p0";

// Verbatim port of 1.14.3 (abb1cb1) lib/features/auth/domain/delegate_login_validator.dart
function egyptianPhoneVariants(normalizedPhone) {
  const variants = new Set([normalizedPhone]);
  if (normalizedPhone.startsWith("0") && normalizedPhone.length === 11) {
    const withoutZero = normalizedPhone.substring(1);
    variants.add(withoutZero);
    variants.add("20" + withoutZero);
    variants.add("+20" + withoutZero);
    variants.add("0020" + withoutZero);
    variants.add("+2" + normalizedPhone);
    variants.add("002" + normalizedPhone);
  }
  return [...variants];
}

const USERS = {
  sa: {role: "super-admin", organizationUID: "o1"},
  sa_: {role: "super_admin", organizationUID: "o1"},
  oa: {role: "organization-admin", organizationUID: "o1"},
  oa_: {role: "organization_admin", organizationUID: "o1"},
  oa2: {role: "organization-admin", organizationUID: "o2"},
  ca: {role: "company-admin", organizationUID: "o1", companyUID: "c1"},
  ca_: {role: "company_admin", organizationUID: "o1", companyUID: "c1"},
  sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
  sup2: {role: "supervisor", organizationUID: "o1", companyUID: "c2"},
  hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
  bmm: {role: "branches_marketing_manager", organizationUID: "o1", companyUID: "c1"},
  mk: {role: "marketing", organizationUID: "o1", companyUID: "c1"},
  ts: {role: "technical_support", organizationUID: "o1"},
  d1: {role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d1", status: "approved"},
  d2: {role: "delegate", organizationUID: "o1", companyUID: "c2", uid: "d2"},
  p1: {role: "promoter", organizationUID: "o1", companyUID: "c1"},
  legacyPw: {role: "hr", organizationUID: "o1", companyUID: "c1", password: "LEGACY-PLACEHOLDER", displayName: "x"},
};

describe("P0 users hardening", () => {
  let env;
  const as = (uid, claims = {}) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}, ...claims}).firestore();
  const anon = (uid = "anon1") => env.authenticatedContext(uid, {firebase: {sign_in_provider: "anonymous"}}).firestore();
  const unauth = () => env.unauthenticatedContext().firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());
  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const [id, d] of Object.entries(USERS)) await db.doc(`users/${id}`).set(d);
      await db.doc("organizations/o1").set({name: "O1", admins: 1});
      await db.doc("organizations/o2").set({name: "O2", admins: 1});
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc("organizations/o1/companies/c2").set({name: "C2"});
      await db.doc("organizations/o2/companies/c9").set({name: "C9"});
      await db.doc("organizations/o1/companies/c1/delegates/del-1").set({
        phoneNumber: "01011111111", organizationUID: "o1", companyUID: "c1", status: "active", nationalityID: "x"});
      await db.doc("organizations/o2/companies/c9/delegates/other").set({
        phoneNumber: "01099999999", organizationUID: "o2", companyUID: "c9", status: "active"});
      await db.doc("invites/i1").set({status: "pending", organizationId: "o1", companyId: "c1",
        roleToAssign: "company-admin", email: "new@example.com"});
    });
  });

  // ---- escalation ----
  test("nobody but a super-admin can create or grant super-admin", async () => {
    for (const u of ["oa", "ca", "sup", "hr", "ts", "mk", "d1", "nodoc"]) {
      await assertFails(as(u).doc(`users/${u}-x`).set({role: "super-admin"}));
      await assertFails(as(u).doc(`users/${u}`).set({role: "super-admin"}, {merge: true}));
    }
    await assertFails(anon().doc("users/anon1").set({role: "super-admin"}));
    await assertFails(unauth().doc("users/u").set({role: "super-admin"}));
    await assertSucceeds(as("sa").doc("users/new").set({role: "super-admin"}));
  });

  test("legacy role spellings behave like canonical ones", async () => {
    await assertSucceeds(as("sa_").doc("users/x").set({role: "hr", organizationUID: "o1", companyUID: "c1"}));
    await assertSucceeds(as("oa_").doc("users/x2").set({role: "hr", organizationUID: "o1", companyUID: "c1"}));
    await assertSucceeds(as("ca_").doc("users/x3").set({role: "delegate", organizationUID: "o1", companyUID: "c1"}));
    await assertFails(as("sa").doc("users/x4").set({role: "super_admin"}));
  });

  test("self create: safe keys only (no role/org/company/status/permissions)", async () => {
    await assertSucceeds(as("nodoc").doc("users/nodoc").set({displayName: "N", fcmToken: "t"}));
    await assertFails(as("nodoc2").doc("users/nodoc2").set({displayName: "N", organizationUID: "o1"}));
    await assertFails(as("nodoc3").doc("users/nodoc3").set({role: "organization-admin"}));
    await assertFails(as("nodoc4").doc("users/nodoc4").set({permissions: ["all"]}));
    await assertFails(as("nodoc5").doc("users/nodoc5").set({status: "Approved"}));
    await assertFails(anon("anon2").doc("users/anon2").set({displayName: "A"}));
  });

  test("self update cannot change role/org/company/status/isActive/permissions", async () => {
    for (const patch of [{role: "organization-admin"}, {organizationUID: "o2"}, {companyUID: "c2"},
      {status: "Approved"}, {isActive: true}, {permissions: ["x"]}, {isSuperAdmin: true}]) {
      await assertFails(as("hr").doc("users/hr").update(patch));
    }
    await assertSucceeds(as("hr").doc("users/hr").update({displayName: "HR", fcmToken: "t", requireReLogin: false}));
  });

  test("no client write may set or change password fields; untouched legacy value is OK (S1)", async () => {
    for (const k of ["password", "temporaryPassword", "tempPassword"]) {
      await assertFails(as("sa").doc("users/pw-" + k).set({role: "hr", [k]: "x"}));
      await assertFails(as("sa").doc("users/hr").update({[k]: "x"}));
      await assertFails(as("hr").doc("users/hr").update({[k]: "x"}));
    }
    await assertSucceeds(as("legacyPw").doc("users/legacyPw").update({displayName: "y"}));
    await assertSucceeds(as("ca").doc("users/legacyPw").update({displayName: "z"}));
    await assertFails(as("legacyPw").doc("users/legacyPw").update({password: "new"}));
  });

  test("org-admin: own org, no privileged roles, no foreign company (N3), no privilege keys", async () => {
    const db = as("oa");
    await assertSucceeds(db.doc("users/n1").set({role: "hr", organizationUID: "o1", companyUID: "c1"}));
    await assertSucceeds(db.doc("users/n2").set({role: "company-admin", organizationUID: "o1", companyUID: "c2"}));
    await assertFails(db.doc("users/n3").set({role: "hr", organizationUID: "o2", companyUID: "c9"}));
    await assertFails(db.doc("users/n4").set({role: "company-admin", organizationUID: "o1", companyUID: "c9"}));
    await assertFails(db.doc("users/n5").set({role: "organization-admin", organizationUID: "o1"}));
    await assertFails(db.doc("users/n6").set({role: "technical_support", organizationUID: "o1"}));
    await assertFails(db.doc("users/n7").set({role: "hr", organizationUID: "o1", companyUID: "c1", permissions: ["x"]}));
    await assertFails(db.doc("users/hr").update({companyUID: "c9"}));
    await assertFails(db.doc("users/hr").update({role: "organization-admin"}));
    await assertFails(db.doc("users/oa_").update({displayName: "x"}));
    await assertFails(db.doc("users/sa").update({displayName: "x"}));
    await assertSucceeds(db.doc("users/hr").update({displayName: "x", isActive: false}));
    await assertFails(as("oa2").doc("users/hr").update({displayName: "x"}));
  });

  test("company staff cannot activate isActive on staff accounts (TA-8)", async () => {
    await assertFails(as("oa").doc("users/hr").update({isActive: true}));
    await assertFails(as("sup").doc("users/hr").update({isActive: true}));
    await assertFails(as("ca").doc("users/sup").update({isActive: true}));
  });

  test("company staff: own company, field roles + non-admin staff only, pinned", async () => {
    await assertSucceeds(as("sup").doc("users/d9").set({role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d9"}));
    await assertFails(as("sup").doc("users/d10").set({role: "delegate", organizationUID: "o1", companyUID: "c2"}));
    await assertFails(as("sup").doc("users/d11").set({role: "delegate", organizationUID: "o2", companyUID: "c1"}));
    await assertFails(as("sup").doc("users/d12").set({role: "company-admin", organizationUID: "o1", companyUID: "c1"}));
    await assertFails(as("sup").doc("users/d1").update({organizationUID: "o2"}));
    await assertFails(as("sup").doc("users/d1").update({companyUID: "c2"}));
    await assertFails(as("sup").doc("users/ca").update({role: "delegate"}));
    await assertFails(as("sup").doc("users/d1").update({status: "suspended", displayName: "D"}));
    await assertFails(as("hr").doc("users/d1").update({status: "SUSPENDED"}));
    await assertFails(as("sup").doc("users/d1").update({isActive: false}));
    await assertSucceeds(as("sup").doc("users/d1").update({displayName: "D"}));
    await assertFails(as("sup2").doc("users/d1").update({displayName: "x"}));
  });

  test("delete: super-admin, and company supervisor/admin for own-company delegates/promoters only", async () => {
    await assertSucceeds(as("sup").doc("users/d1").delete());
    await assertSucceeds(as("ca").doc("users/p1").delete());
    await assertFails(as("sup").doc("users/d2").delete());
    await assertFails(as("sup").doc("users/hr").delete());
    await assertFails(as("oa").doc("users/d2").delete());
    await assertFails(as("hr").doc("users/p1").delete());
    await assertFails(as("ts").doc("users/d2").delete());
    await assertFails(as("bmm").doc("users/mk").delete());
    await assertFails(as("d1").doc("users/d2").delete());
    await assertSucceeds(as("sa").doc("users/hr").delete());
    await assertFails(as("sa").doc("users/sa").delete());
  });

  test("reads: other company/org denied, own doc OK, unscoped list denied", async () => {
    await assertSucceeds(as("hr").doc("users/hr").get());
    await assertFails(as("sup2").doc("users/d1").get());
    await assertFails(as("oa2").doc("users/hr").get());
    await assertFails(as("d1").doc("users/d2").get());
    await assertFails(anon().doc("users/hr").get());
    await assertFails(as("oa").collection("users").get());
    await assertSucceeds(as("oa").collection("users").where("organizationUID", "==", "o1").get());
    await assertSucceeds(as("sa").collection("users").get());
  });

  // ---- members / invites (A1 forgery) ----
  test("forged A1: members self-write and self role are denied", async () => {
    const db = as("nodoc");
    await assertFails(db.doc("organizations/o1/members/nodoc").set({role: "org-admin"}));
    await assertFails(db.doc("organizations/o1/companies/c1/members/nodoc").set({role: "company-admin"}));
    await assertFails(db.doc("users/nodoc").set({role: "organization-admin", organizationUID: "o1"}));
    await assertFails(db.doc("invites/i1").update({status: "claimed", claimedByUid: "nodoc"}));
    await assertSucceeds(as("oa").doc("organizations/o1/members/m1").set({role: "x"}));
    await assertFails(as("oa2").doc("organizations/o1/members/m1").set({role: "x"}));
  });

  test("invites: get by id public, list scoped, E1 role/expiry/org checks", async () => {
    await assertSucceeds(unauth().doc("invites/i1").get());
    await assertFails(unauth().collection("invites").get());
    await assertFails(as("d1").collection("invites").get());
    await assertSucceeds(as("oa").collection("invites").where("organizationId", "==", "o1").get());
    const exp = (days) => Timestamp.fromMillis(Date.now() + days * 86400000);
    const base = {status: "pending", organizationId: "o1", companyId: "c1", roleToAssign: "company-admin", email: "a@b.c"};
    await assertSucceeds(as("oa").doc("invites/n1").set({...base, expiresAt: exp(7)}));
    await assertFails(as("oa").doc("invites/n2").set({...base, expiresAt: exp(8)}));
    await assertFails(as("oa").doc("invites/n3").set({...base}));
    await assertFails(as("oa").doc("invites/n4").set({...base, roleToAssign: "org-admin", expiresAt: exp(1)}));
    await assertFails(as("oa").doc("invites/n5").set({...base, roleToAssign: "super-admin", expiresAt: exp(1)}));
    await assertFails(as("sa").doc("invites/n6").set({...base, roleToAssign: "super-admin", expiresAt: exp(1)}));
    await assertSucceeds(as("sa").doc("invites/n7").set({...base, companyId: null, roleToAssign: "org-admin", expiresAt: exp(1)}));
    await assertFails(as("oa").doc("invites/n8").set({...base, organizationId: "o2", companyId: "c9", expiresAt: exp(1)}));
    await assertFails(as("oa").doc("invites/n9").set({...base, companyId: "c9", expiresAt: exp(1)}));
    await assertFails(as("sa").doc("invites/n10").set({...base, organizationId: "nope", expiresAt: exp(1)}));
  });

  // ---- delegates: login regression (rules unchanged by P0) ----
  test("1.14.3 delegate login query (collectionGroup whereIn variants) passes after custom token; foreign/anon denied", async () => {
    const claims = {role: "delegate", delegateId: "del-1", delegateIds: ["del-1"], orgId: "o1", companyId: "c1",
      phones: egyptianPhoneVariants("01011111111"), firebase: {sign_in_provider: "custom"}};
    const db = env.authenticatedContext("del-1", claims).firestore();
    const variants = egyptianPhoneVariants("01011111111");
    const snap = await assertSucceeds(db.collectionGroup("delegates").where("phoneNumber", "in", variants).get());
    if (snap.size !== 1) throw new Error("expected own delegate doc, got " + snap.size);
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertFails(db.collectionGroup("delegates").where("phoneNumber", "in", [...variants, "01099999999"]).get());
    await assertFails(db.doc("organizations/o2/companies/c9/delegates/other").get());
    await assertFails(anon().collectionGroup("delegates").where("phoneNumber", "in", variants).get());
  });
});
