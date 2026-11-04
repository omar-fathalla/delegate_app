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
  fn = require("../../functions/lib/index.js");
  db = admin.firestore();
  await db.doc("organizations/o1").set({name: "O"});
  await db.doc("organizations/o1/companies/c1").set({name: "C"});
  await db.doc("users/sa").set({role: "super-admin"});
  await db.doc("users/ca").set({role: "company-admin", organizationUID: "o1", companyUID: "c1"});
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
});

test("claimInvite: verified email claims once; unverified refused", async () => {
  const exp = admin.firestore.Timestamp.fromMillis(Date.now() + 86400000);
  await db.doc("invites/i1").set({email: "inv@e.com", roleToAssign: "company-admin", organizationId: "o1",
    companyId: "c1", companyName: "C", status: "pending", expiresAt: exp, invitedByUid: "sa"});
  assert.equal(await code(fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u1", {email: "inv@e.com", email_verified: false}))), "email_not_verified");
  const r = await fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u1", {email: "inv@e.com", email_verified: true}));
  assert.equal(r.status, "claimed");
  assert.equal((await db.doc("users/u1").get()).data().role, "company-admin");
  assert.ok((await db.doc("organizations/o1/companies/c1/members/u1").get()).exists);
  assert.equal((await db.doc("organizations/o1/companies/c1").get()).data().admins, 1);
  assert.equal(await code(fn.claimInvite.run({inviteId: "i1", displayName: "I"}, ctx("u2", {email: "inv@e.com", email_verified: true}))), "invite_not_pending");
});
