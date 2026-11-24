/**
 * createStaffUser / resendStaffSetupLink / claimInvite against the Auth +
 * Firestore emulators (handlers run in-process via the v1 callable .run()).
 * Staff accounts only; delegate login is covered by delegate-login.e2e.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../../functions/node_modules/firebase-admin");

let fn; let db;
const ctx = (uid, extra = {}) => ({auth: {uid, token: {firebase: {sign_in_provider: "password"}, ...extra}}, rawRequest: {headers: {}}});

test.before(async () => {
  process.env.STAFF_CREATE_ENABLED = "true";
  fn = require("../../functions/lib/index.js");
  db = admin.firestore();
  await db.doc("organizations/o1").set({name: "O"});
  await db.doc("organizations/o1/companies/c1").set({name: "C"});
  await db.doc("users/sa").set({role: "super-admin"});
  await db.doc("users/ca").set({role: "company-admin", organizationUID: "o1", companyUID: "c1"});
  await db.doc("users/sup").set({role: "supervisor", organizationUID: "o1", companyUID: "c1"});
  await db.doc("users/hr2").set({role: "hr", organizationUID: "o1", companyUID: "c1"});
  await db.doc("users/del").set({role: "delegate", organizationUID: "o1", companyUID: "c1"});
});
test.after(async () => { await Promise.all(admin.apps.map((a) => a && a.delete())); });

async function code(p) { try { await p; return "ok"; } catch (e) { return e.details?.reason || e.code; } }

test("super-admin creates staff: Auth user with no password, no password in Firestore, link only in mail", async () => {
  const r = await fn.createStaffUser.run({email: "New.HR@Example.com", phoneNumber: "01234567890",
    displayName: "HR", role: "hr", organizationUID: "o1", companyUID: "c1"}, ctx("sa"));
  assert.deepEqual(Object.keys(r), ["uid"]);
  const u = await admin.auth().getUser(r.uid);
  assert.equal(u.email, "new.hr@example.com");
  assert.equal(u.passwordHash, undefined);
  const doc = (await db.doc(`users/${r.uid}`).get()).data();
  for (const k of ["password", "temporaryPassword", "tempPassword"]) assert.equal(doc[k], undefined);
  assert.equal(doc.role, "hr");
  const mail = await db.collection("mail").where("to", "array-contains", "new.hr@example.com").get();
  assert.equal(mail.size, 1);
  assert.ok(mail.docs[0].data().message.html.includes("oobCode"));
  assert.equal(await code(fn.createStaffUser.run({email: "x2@example.com", phoneNumber: "01234567890",
    displayName: "D", role: "hr", organizationUID: "o1", companyUID: "c1"}, ctx("sa"))), "phone_taken");
  assert.equal(await code(fn.resendStaffSetupLink.run({uid: r.uid}, ctx("ca"))), "ok");
});

test("scope and staff-only checks", async () => {
  const base = {phoneNumber: "01200000001", displayName: "X", organizationUID: "o1", companyUID: "c1"};
  assert.equal(await code(fn.createStaffUser.run({...base, email: "a@e.com", role: "super-admin"}, ctx("sa"))), "super_admin_not_creatable");
  assert.equal(await code(fn.createStaffUser.run({...base, email: "b@e.com", role: "delegate"}, ctx("sa"))), "not_staff_role");
  assert.equal(await code(fn.createStaffUser.run({...base, email: "c@e.com", role: "company-admin"}, ctx("ca"))), "role_not_allowed");
  assert.equal(await code(fn.createStaffUser.run({...base, email: "d@e.com", role: "hr"}, ctx("del"))), "caller_not_allowed");
  assert.equal(await code(fn.createStaffUser.run({...base, email: "e@e.com", role: "hr"}, {rawRequest: {headers: {}}})), "sign_in_required");
  // #205 review: supervisor / HR cannot create any staff role.
  for (const r of ["marketing", "branches_marketing_manager", "accountant", "hr", "supervisor"]) {
    assert.equal(await code(fn.createStaffUser.run({...base, email: `s-${r}@e.com`, role: r}, ctx("sup"))), "role_not_allowed", r);
  }
});

test("rate limit runs before lookups (no unmetered phone/email oracle)", async () => {
  const base = {displayName: "X", role: "hr", organizationUID: "o1", companyUID: "c1", email: "taken@e.com"};
  const seen = [];
  for (let i = 0; i < 6; i++) seen.push(await code(fn.createStaffUser.run({...base, phoneNumber: "01234567890"}, ctx("hr2"))));
  assert.deepEqual(seen.slice(0, 5), Array(5).fill("role_not_allowed"));
  assert.equal(seen[5], "rate_limited");
});

test("resendStaffSetupLink: missing uid looks like out_of_scope for non-global callers", async () => {
  assert.equal(await code(fn.resendStaffSetupLink.run({uid: "nope"}, ctx("ca"))), "out_of_scope");
  assert.equal(await code(fn.resendStaffSetupLink.run({uid: "sa"}, ctx("ca"))), "super_admin_not_creatable");
  assert.equal(await code(fn.resendStaffSetupLink.run({uid: "nope"}, ctx("sa"))), "not_found");
});

test("kill switch: disabled by default", async () => {
  delete process.env.STAFF_CREATE_ENABLED;
  assert.equal(await code(fn.createStaffUser.run({email: "k@e.com", phoneNumber: "01299999999", displayName: "K",
    role: "hr", organizationUID: "o1", companyUID: "c1"}, ctx("sa"))), "staff_create_disabled");
  assert.equal(await code(fn.resendStaffSetupLink.run({uid: "ca"}, ctx("sa"))), "staff_create_disabled");
  process.env.STAFF_CREATE_ENABLED = "true";
});

test("claimInvite: the invite link proves the email (TAS-68); claims once", async () => {
  const exp = admin.firestore.Timestamp.fromMillis(Date.now() + 86400000);
  await db.doc("invites/i1").set({email: "inv@e.com", roleToAssign: "company-admin", organizationId: "o1",
    companyId: "c1", companyName: "C", status: "pending", expiresAt: exp, invitedByUid: "sa"});
  // TAS-68: finish-signup signs up with a password, so the email is not verified yet.
  assert.equal((await fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u1", {email: "inv@e.com", email_verified: false}))).status, "claimed");
  // A different email is still refused, verified or not.
  await db.doc("invites/i9").set({email: "other@e.com", roleToAssign: "company-admin", organizationId: "o1",
    companyId: "c1", companyName: "C", status: "pending", expiresAt: exp, invitedByUid: "sa"});
  assert.equal(await code(fn.claimInvite.run({inviteId: "i9", displayName: "I"}, ctx("u3", {email: "inv@e.com", email_verified: true}))), "email_mismatch");
  const r = await fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u1", {email: "inv@e.com", email_verified: true}));
  assert.equal(r.status, "claimed");
  assert.equal((await db.doc("users/u1").get()).data().role, "company-admin");
  assert.ok((await db.doc("organizations/o1/companies/c1/members/u1").get()).exists);
  assert.equal((await db.doc("organizations/o1/companies/c1").get()).data().admins, 1);
  assert.equal(await code(fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u2", {email: "inv@e.com", email_verified: true}))), "invite_already_claimed");
  // Safe retry: same caller gets the same result, nothing double-counted.
  const again = await fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u1", {email: "inv@e.com", email_verified: true}));
  assert.equal(again.status, "claimed");
  assert.equal((await db.doc("organizations/o1/companies/c1").get()).data().admins, 1);
  // Rate limit on claimInvite (5/hour per uid; u1 has used 3).
  const r2 = [];
  for (let i = 0; i < 3; i++) r2.push(await code(fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u1", {email: "inv@e.com", email_verified: true}))));
  assert.deepEqual(r2, ["ok", "ok", "rate_limited"]);
});
