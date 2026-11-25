/**
 * TAS-15 / TAS-17: what an anonymous token, or a self-registered
 * email/password account (no users doc, no claims), can reach under the
 * dev rules.
 *
 * Both Firebase Auth doors stay open on production until the forced update
 * (TAS-66): store builds up to v1.14.0 still call signInAnonymously, and
 * Identity Platform still lets anyone create an email/password account with
 * the public API key. These tests pin that the rules give such tokens
 * nothing beyond what a signed-out visitor gets, so closing the Auth doors
 * later is a config change only, with no rules change.
 *
 *   npm run test:rules:tas15-17
 *
 * Budget note (TAS-105): for a password token with no users doc and no role
 * claim, three reads (another user's users doc, a delegate doc, a
 * notification) are denied by the 1000-expression budget, not by a rule
 * condition. They were denied that way before this file existed; the 9 in
 * expression-budget-baseline.json are those 3 reads x 3 identities.
 */
"use strict";
const {describe, test, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("./_rules_testing");
const {
  Timestamp, doc, setDoc, updateDoc, getDoc, getDocs, addDoc, collection, collectionGroup, query, where,
} = require("firebase/firestore");
const {ref, uploadBytes, getBytes} = require("firebase/storage");

function splitHost(envName, fallback) {
  const raw = process.env[envName] || fallback;
  const [host, port] = raw.split(":");
  return {host, port: Number(port)};
}

const bytes = Uint8Array.from(Buffer.from("tas15-17 fixture\n"));
const PHONE = "01011111111";
const VICTIM_PHONE = "01000000009";
const VICTIM_EMAIL = "victim@x.test";

// The three outsider identities. None has a users doc or role claims.
const OUTSIDERS = {
  anonymous: {uid: "anon1", token: {firebase: {sign_in_provider: "anonymous"}}},
  selfSignup: {uid: "self1", token: {email: "self1@x.test", firebase: {sign_in_provider: "password"}}},
  // TAS-17: a self-registered account that also claims the victim's email in
  // its token (sign-up with an address it does not own, unverified).
  selfSignupVictimEmail: {
    uid: "self2",
    token: {email: VICTIM_EMAIL, email_verified: false, firebase: {sign_in_provider: "password"}},
  },
};

describe("TAS-15/17: anonymous and self-registered tokens", () => {
  let env;
  const fsHost = splitHost("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080");
  const stHost = splitHost("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199");

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-tas15-17",
      firestore: {
        host: fsHost.host, port: fsHost.port,
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
      storage: {
        host: stHost.host, port: stHost.port,
        rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8"),
      },
    });
  });

  after(async () => {
    if (env) await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/victim"), {
        role: "organization-admin", organizationUID: "o1", phoneNumber: VICTIM_PHONE, email: VICTIM_EMAIL,
      });
      await setDoc(doc(db, "users/hr1"), {role: "hr", organizationUID: "o1", companyUID: "c1"});
      await setDoc(doc(db, "organizations/o1"), {name: "Org"});
      await setDoc(doc(db, "organizations/o1/companies/c1"), {name: "Co", organizationUID: "o1"});
      await setDoc(doc(db, "organizations/o1/companies/c1/delegates/d1"), {
        phoneNumber: PHONE, organizationUID: "o1", companyUID: "c1", status: "active", name: "D",
      });
      await setDoc(doc(db, "invites/i1"), {
        status: "pending", organizationId: "o1", companyId: "c1", roleToAssign: "company-admin",
        email: "new@x.test", expiresAt: Timestamp.fromMillis(Date.now() + 86400000),
      });
      await setDoc(doc(db, "branches/b1"), {name: "B", organizationUID: "o1"});
      await setDoc(doc(db, "config/delegate_auth"), {otpEnforcementEnabled: false});
      await setDoc(doc(db, "notifications/n1"), {targetUid: "d1", title: "t"});
      await setDoc(doc(db, "attendance_logs/a1"), {delegateUid: "d1", organizationId: "o1", companyId: "c1"});
      await setDoc(doc(db, "delegate_requests/r1"), {organizationUID: "o1", companyUID: "c1", status: "pending"});
    });
    await env.withSecurityRulesDisabled(async (ctx) => {
      const st = ctx.storage();
      await uploadBytes(ref(st, "delegate_documents/d1/id.png"), bytes, {contentType: "image/png"});
      await uploadBytes(ref(st, "organizations/o1/companies/c1/delegates/d1/personalPhoto/p.png"), bytes,
        {contentType: "image/png"});
    });
  });

  const fsOf = (o) => env.authenticatedContext(o.uid, o.token).firestore();
  const stOf = (o) => env.authenticatedContext(o.uid, o.token).storage();
  const signedOutFs = () => env.unauthenticatedContext().firestore();

  // Every probe must be denied for every outsider identity.
  function firestoreProbes(db, uid) {
    return {
      "get another user's users doc": () => getDoc(doc(db, "users/victim")),
      "list users by victim phone": () => getDocs(query(collection(db, "users"), where("phoneNumber", "==", VICTIM_PHONE))),
      "list users by victim email": () => getDocs(query(collection(db, "users"), where("email", "==", VICTIM_EMAIL))),
      "create own users doc as organization-admin": () =>
        setDoc(doc(db, `users/${uid}`), {uid, role: "organization-admin", organizationUID: "o1"}),
      "create own users doc with the victim phone": () =>
        setDoc(doc(db, `users/${uid}`), {uid, role: "delegate", phoneNumber: VICTIM_PHONE}),
      "get a delegate doc": () => getDoc(doc(db, "organizations/o1/companies/c1/delegates/d1")),
      "query delegates by phone (collection group)": () =>
        getDocs(query(collectionGroup(db, "delegates"), where("phoneNumber", "==", PHONE))),
      "update a delegate phone/status (TAS-28)": () =>
        updateDoc(doc(db, "organizations/o1/companies/c1/delegates/d1"), {phoneNumber: "01099999999", status: "suspended"}),
      "create a delegate": () =>
        setDoc(doc(db, "organizations/o1/companies/c1/delegates/" + uid), {phoneNumber: PHONE, status: "active"}),
      "get organization": () => getDoc(doc(db, "organizations/o1")),
      "update organization": () => updateDoc(doc(db, "organizations/o1"), {name: "x"}),
      "get company": () => getDoc(doc(db, "organizations/o1/companies/c1")),
      "queue a mail doc": () => addDoc(collection(db, "mail"), {to: "a@x.test", message: {subject: "s", html: "h"}}),
      "broadcast a notification": () => addDoc(collection(db, "notifications"), {targetUid: "d1", title: "t"}),
      "read a notification": () => getDoc(doc(db, "notifications/n1")),
      "list invites": () => getDocs(collection(db, "invites")),
      "create an invite": () => setDoc(doc(db, "invites/x" + uid), {
        status: "pending", organizationId: "o1", roleToAssign: "org-admin", email: "a@x.test",
      }),
      "claim an invite from the client": () => updateDoc(doc(db, "invites/i1"), {status: "claimed", claimedByUid: uid}),
      "read attendance": () => getDoc(doc(db, "attendance_logs/a1")),
      "write attendance": () => addDoc(collection(db, "attendance_logs"), {delegateUid: uid, organizationId: "o1"}),
      "read a delegate request": () => getDoc(doc(db, "delegate_requests/r1")),
      "create a delegate request": () => addDoc(collection(db, "delegate_requests"), {organizationUID: "o1", status: "pending"}),
      "mint a storage upload intent": () => setDoc(doc(db, "storage_upload_intents/f1"), {companyUID: "c1"}),
      "read a branch": () => getDoc(doc(db, "branches/b1")),
      "read config/delegate_auth": () => getDoc(doc(db, "config/delegate_auth")),
    };
  }

  function storageProbes(st) {
    return {
      "read a delegate document file": () => getBytes(ref(st, "delegate_documents/d1/id.png")),
      "upload into a delegate document folder": () =>
        uploadBytes(ref(st, "delegate_documents/d1/x.png"), bytes, {contentType: "image/png"}),
      "read a delegate photo": () => getBytes(ref(st, "organizations/o1/companies/c1/delegates/d1/personalPhoto/p.png")),
      "upload a delegate photo": () => uploadBytes(
        ref(st, "organizations/o1/companies/c1/delegates/d1/personalPhoto/x.png"), bytes, {contentType: "image/png"}),
    };
  }

  // Runs every probe and reports all the ones that were allowed at once.
  async function expectAllDenied(who, probes) {
    const allowed = [];
    for (const [label, run] of Object.entries(probes)) {
      try {
        await assertFails(run());
      } catch (e) {
        allowed.push(label);
      }
    }
    assert.deepEqual(allowed, [], `${who}: allowed ${allowed.join(", ")}`);
  }

  for (const [name, who] of Object.entries(OUTSIDERS)) {
    test(`${name}: every Firestore probe is denied`, async () => {
      await expectAllDenied(name, firestoreProbes(fsOf(who), who.uid));
    });

    test(`${name}: every Storage probe is denied`, async () => {
      await expectAllDenied(name, storageProbes(stOf(who)));
    });
  }

  test("anonymous cannot even create a bare users doc for itself", async () => {
    await assertFails(setDoc(doc(fsOf(OUTSIDERS.anonymous), "users/anon1"), {uid: "anon1", role: "delegate"}));
    await assertFails(setDoc(doc(fsOf(OUTSIDERS.anonymous), "users/anon1"), {uid: "anon1"}));
  });

  test("a self-registered account with a bare self-created users doc still gets nothing", async () => {
    const who = OUTSIDERS.selfSignup;
    const db = fsOf(who);
    // Legacy self-create (role '' / delegate, no tenant, no contact fields)
    // is still allowed. It must not unlock anything.
    await assertSucceeds(setDoc(doc(db, `users/${who.uid}`), {uid: who.uid, role: ""}));
    const probes = firestoreProbes(db, who.uid);
    delete probes["create own users doc as organization-admin"];
    delete probes["create own users doc with the victim phone"];
    await expectAllDenied("selfSignup+doc", probes);
    await assertFails(updateDoc(doc(db, `users/${who.uid}`), {role: "organization-admin"}));
    await assertFails(updateDoc(doc(db, `users/${who.uid}`), {phoneNumber: VICTIM_PHONE}));
    await assertFails(updateDoc(doc(db, `users/${who.uid}`), {organizationUID: "o1"}));
  });

  test("the only thing open to outsiders is open to signed-out visitors too: invite by id", async () => {
    // finish-signup reads the invite by its unguessable id before any sign-in.
    await assertSucceeds(getDoc(doc(signedOutFs(), "invites/i1")));
    for (const who of Object.values(OUTSIDERS)) {
      await assertSucceeds(getDoc(doc(fsOf(who), "invites/i1")));
    }
  });

  test("control: a real staff token still reads its own tenant (fixtures are reachable)", async () => {
    const hr = env.authenticatedContext("hr1", {firebase: {sign_in_provider: "password"}}).firestore();
    await assertSucceeds(getDoc(doc(hr, "organizations/o1/companies/c1/delegates/d1")));
    assert.ok(true);
  });
});
