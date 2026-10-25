/**
 * Firestore rules tests for the super-admin role string.
 *
 * Rules grant isSuperAdmin() only when users/{uid}.role == "super-admin".
 * They do not read custom claims, and they do not accept "super_admin".
 * These tests run against the local emulator only (project demo-tashil-rules).
 *
 * The users collection currently allows any authenticated client to create or
 * update any user document, with no restriction on the role field. The
 * self-assign tests below lock that current behavior in so a future tightening
 * is visible. They are not a request to loosen the rules.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const PROJECT_ID = "demo-tashil-rules";

describe("firestore super-admin role", () => {
  /** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/super").set({role: "super-admin"});
      await db.doc("users/legacy").set({role: "super_admin"});
      await db.doc("users/delegate").set({role: "delegate"});
      await db.doc("organizations/existing").set({name: "Existing"});
      await db.doc("invites/invite1").set({status: "pending"});
      await db.doc("mail/mail1").set({to: "a@b.c"});
      await db.doc("guide_videos/vid1").set({title: "intro"});
      await db.doc("app_updates/upd1").set({version: "1"});
      await db.doc("notifications/note1").set({title: "hello"});
    });
  });

  function dbFor(uid, claims) {
    return testEnv.authenticatedContext(uid, claims).firestore();
  }

  test("super-admin can create and delete organizations", async () => {
    const db = dbFor("super");
    await assertSucceeds(
      db.collection("organizations").doc("created").set({name: "N"}),
    );
    await assertSucceeds(db.doc("organizations/existing").delete());
  });

  test("a delegate cannot create or delete organizations", async () => {
    const db = dbFor("delegate");
    await assertFails(
      db.collection("organizations").doc("created").set({name: "N"}),
    );
    await assertFails(db.doc("organizations/existing").delete());
  });

  test("a user doc stored as super_admin is not treated as super-admin", async () => {
    const db = dbFor("legacy");
    await assertFails(
      db.collection("organizations").doc("created").set({name: "N"}),
    );
    await assertFails(db.doc("organizations/existing").delete());
    await assertFails(db.doc("invites/invite1").delete());
    await assertFails(db.doc("mail/mail1").get());
    await assertFails(db.doc("guide_videos/vid1").set({title: "x"}));
    await assertFails(db.doc("app_updates/upd1").set({version: "2"}));
  });

  test("a custom claim does not grant super-admin access", async () => {
    const db = dbFor("delegate", {role: "super-admin"});
    await assertFails(
      db.collection("organizations").doc("created").set({name: "N"}),
    );
    await assertFails(db.doc("invites/invite1").delete());
  });

  test("super-admin can delete invites and a delegate cannot", async () => {
    await assertSucceeds(dbFor("super").doc("invites/invite1").delete());
  });

  test("a delegate cannot delete invites", async () => {
    await assertFails(dbFor("delegate").doc("invites/invite1").delete());
  });

  test("super-admin can read, update, and delete mail", async () => {
    const db = dbFor("super");
    await assertSucceeds(db.doc("mail/mail1").get());
    await assertSucceeds(db.doc("mail/mail1").update({to: "c@d.e"}));
    await assertSucceeds(db.doc("mail/mail1").delete());
  });

  test("a delegate cannot read, update, or delete mail", async () => {
    const db = dbFor("delegate");
    await assertFails(db.doc("mail/mail1").get());
    await assertFails(db.doc("mail/mail1").update({to: "c@d.e"}));
    await assertFails(db.doc("mail/mail1").delete());
  });

  test("super-admin can write guide videos and app updates", async () => {
    const db = dbFor("super");
    await assertSucceeds(db.doc("guide_videos/vid1").set({title: "updated"}));
    await assertSucceeds(db.doc("guide_videos/new").set({title: "new"}));
    await assertSucceeds(db.doc("app_updates/upd1").set({version: "2"}));
    await assertSucceeds(db.doc("app_updates/new").set({version: "3"}));
  });

  test("a delegate cannot write guide videos or app updates", async () => {
    const db = dbFor("delegate");
    await assertFails(db.doc("guide_videos/vid1").set({title: "updated"}));
    await assertFails(db.doc("guide_videos/new").set({title: "new"}));
    await assertFails(db.doc("app_updates/upd1").set({version: "2"}));
    await assertFails(db.doc("app_updates/new").set({version: "3"}));
  });

  test("an authenticated user can self-assign super-admin and then pass isSuperAdmin", async () => {
    const db = dbFor("self");
    await assertSucceeds(db.doc("users/self").set({role: "delegate"}));
    await assertFails(
      db.collection("organizations").doc("before").set({name: "no"}),
    );
    await assertSucceeds(db.doc("users/self").update({role: "super-admin"}));
    await assertSucceeds(
      db.collection("organizations").doc("after").set({name: "yes"}),
    );
  });

  test("an authenticated user can assign super-admin on another user document", async () => {
    const db = dbFor("delegate");
    await assertSucceeds(db.doc("users/victim").set({role: "super-admin"}));
    const victim = dbFor("victim");
    await assertSucceeds(
      victim.collection("organizations").doc("via-other").set({name: "yes"}),
    );
  });

  test("an unauthenticated client cannot write a super-admin user document", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc("users/anon").set({role: "super-admin"}));
  });

  test("notification delete is not super-admin-only because a later match allows write", async () => {
    // match /notifications allows delete only for isSuperAdmin, then a second
    // match /notifications allows read, write if true. Firestore ORs allows,
    // so the second match wins. This records that fact; it does not change it.
    await assertSucceeds(dbFor("delegate").doc("notifications/note1").delete());
    await assertSucceeds(
      testEnv.unauthenticatedContext().firestore().doc("notifications/open").set({
        title: "open",
      }),
    );
    let deleted = false;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await ctx.firestore().doc("notifications/note1").get();
      deleted = snap.exists === false;
    });
    assert.equal(deleted, true);
  });
});
