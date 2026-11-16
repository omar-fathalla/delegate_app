/**
 * C1: hardened web claimInvite$ batch (rules-only; inviteId via auth token claim).
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {
  doc, setDoc, writeBatch, updateDoc, serverTimestamp, increment, Timestamp,
} = require("firebase/firestore");

const PROJECT_ID = "demo-invite-claim-batch";
const ORG = "o1";
const CO = "c1";
const RULES = readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8");

const exp = () => Timestamp.fromMillis(Date.now() + 3 * 86400000);

function ctx(env, uid, email, extra = {}) {
  return env.authenticatedContext(uid, {
    email,
    email_verified: extra.email_verified !== false,
    firebase: {sign_in_provider: "password"},
  ...extra,
  }).firestore();
}

async function seedInvite(env, id, email, org = ORG, co = CO) {
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, `organizations/${org}`), {name: "org", admins: 1, companies: 1, status: "active"});
    await setDoc(doc(db, `organizations/${org}/companies/${co}`), {
      name: "co", admins: 1, delegates: 0, organizationUID: org, status: "Active",
    });
    await setDoc(doc(db, "invites/" + id), {
      email, status: "pending", roleToAssign: "company-admin",
      organizationId: org, companyId: co, expiresAt: exp(), invitedByUid: "oa",
    });
  });
}

function webBatch(db, uid, email, org, co, inviteId, opts = {}) {
  const b = writeBatch(db);
  const role = opts.wrongRole ? "organization-admin" : "company-admin";
  const userCo = opts.wrongCompany ? "c9" : co;
  b.set(doc(db, `organizations/${org}/companies/${co}/members/${uid}`), {
    role, status: "active", displayName: "n", createdAt: serverTimestamp(), invitedBy: "oa",
  });
  b.set(doc(db, `users/${uid}`), {
    uid, email, displayName: "n", phoneNumber: null, role: opts.wrongRole ? "organization-admin" : "company-admin",
    emailVerified: opts.forgeEmailVerified === true,
    organizationUID: org, organizationName: "org",
    companyUID: userCo, companyName: "co", status: "Approved",
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  const bump = opts.adminBump === 2 ? 2 : 1;
  b.update(doc(db, `organizations/${org}/companies/${co}`), {admins: increment(bump), updatedAt: serverTimestamp()});
  const invEmail = opts.foreignInvite ? "other@x.test" : email;
  b.update(doc(db, `invites/${inviteId}`), {
    status: "claimed", claimedAt: serverTimestamp(), claimedByUid: uid,
    claimedByEmail: invEmail, updatedAt: serverTimestamp(),
  });
  return b.commit();
}

describe("invite claim batch (C1)", () => {
  let env;

  before(async () => {
    env = await initializeTestEnvironment({projectId: PROJECT_ID, firestore: {rules: RULES}});
  });
  after(async () => env.cleanup());
  beforeEach(async () => env.clearFirestore());

  test("web-shaped batch passes with verified token + inviteId claim", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "u1", "good@x.test", {inviteId: "i1"});
    await assertSucceeds(webBatch(db, "u1", "good@x.test", ORG, CO, "i1"));
  });

  test("deny forged client emailVerified without token verification", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "u2", "good@x.test", {inviteId: "i1", email_verified: false});
    await assertFails(webBatch(db, "u2", "good@x.test", ORG, CO, "i1", {forgeEmailVerified: true}));
  });

  test("deny wrong token email", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "u3", "wrong@x.test", {inviteId: "i1"});
    await assertFails(webBatch(db, "u3", "wrong@x.test", ORG, CO, "i1"));
  });

  test("deny unverified email token", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "u4", "good@x.test", {inviteId: "i1", email_verified: false});
    await assertFails(webBatch(db, "u4", "good@x.test", ORG, CO, "i1"));
  });

  test("deny wrong company on user doc", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "u5", "good@x.test", {inviteId: "i1"});
    await assertFails(webBatch(db, "u5", "good@x.test", ORG, CO, "i1", {wrongCompany: true}));
  });

  test("deny admins increment +2", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "u6", "good@x.test", {inviteId: "i1"});
    await assertFails(webBatch(db, "u6", "good@x.test", ORG, CO, "i1", {adminBump: 2}));
  });

  test("deny claiming another invite email on update", async () => {
    await seedInvite(env, "i1", "good@x.test");
    await seedInvite(env, "i2", "victim@x.test");
    const db = ctx(env, "u7", "good@x.test", {inviteId: "i1"});
    await assertFails(webBatch(db, "u7", "good@x.test", ORG, CO, "i2"));
  });

  test("deny self member without invite batch", async () => {
    await seedInvite(env, "i1", "good@x.test");
    const db = ctx(env, "nodoc", "good@x.test", {inviteId: "i1"});
    await assertFails(setDoc(doc(db, `organizations/${ORG}/companies/${CO}/members/nodoc`), {role: "company-admin"}));
  });
});