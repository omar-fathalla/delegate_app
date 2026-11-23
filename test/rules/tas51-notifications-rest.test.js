/**
 * TAS-51 (rest): what was left after the staff part (#494).
 * - A delegate notifies one person only (its company supervisors or one uid),
 *   never a broadcast.
 * - Company notifications (nested): delegates no longer edit them; company
 *   staff only flip the read flags.
 * - Shared notifications are read / hidden per user (readBy / deletedBy with
 *   the caller's own ids); isRead on a shared doc is refused.
 * Every deny must come from a rule, not the 1000-expression budget.
 * Fake data only.
 *
 * npm run test:rules:tas51-rest
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, updateDoc, addDoc, collection, serverTimestamp, arrayUnion} = require("firebase/firestore");

const ORG = "seed-fake-tas51r-org";
const CO = "seed-fake-tas51r-co";
const CO_B = "seed-fake-tas51r-co-b";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas51-rest",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/admin-a"), {role: "company-admin", organizationUID: ORG, companyUID: CO, fake: true});
    await setDoc(doc(db, "users/admin-b"), {role: "company-admin", organizationUID: ORG, companyUID: CO_B, fake: true});
    await setDoc(doc(db, "users/hr-a"), {role: "hr", organizationUID: ORG, companyUID: CO, fake: true});
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/notifications/cn1`), {
      message: "Fake", read: false, companyUID: CO, fake: true,
    });
    await setDoc(doc(db, "notifications/shared-all"), {
      delegateUid: "all", title: "Fake", isRead: false, readBy: ["someone-else"], deletedBy: [], fake: true,
    });
    await setDoc(doc(db, "notifications/own-del"), {
      delegateUid: "del-a", title: "Fake", isRead: false, companyUID: CO, fake: true,
    });
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const delegate = (uid = "del-a") => env.authenticatedContext(uid, {
  role: "delegate", orgId: ORG, companyId: CO, delegateId: uid,
}).firestore();

const delegateNotif = (over) => ({
  title: "Fake", body: "b", type: "attendance_check_in", isRead: false, read: false,
  deletedBy: [], companyId: CO, companyUID: CO, organizationId: ORG, organizationUID: ORG,
  createdBy: "del-a", createdAt: serverTimestamp(), ...over,
});

describe("delegate creates", () => {
  test("delegate notifies its company supervisors (attendance / tracking)", async () => {
    await assertSucceeds(addDoc(collection(delegate(), "notifications"),
      delegateNotif({delegateUid: `supervisor_${CO}`})));
  });
  test("delegate notifies its own supervisor by uid (leave request)", async () => {
    await assertSucceeds(addDoc(collection(delegate(), "notifications"),
      delegateNotif({delegateUid: "SupervisorUid0000000000000001"})));
  });
  for (const target of ["all", "delegates", `delegates_${CO}`, `company_${CO}`, `supervisor_${CO_B}`,
    "all_company_supervisors", "organizationAdmin", "super-admin", "marketing", "role_super_admin"]) {
    test(`delegate cannot broadcast to ${target}`, async () => {
      await assertDeniedByRule(addDoc(collection(delegate(), "notifications"), delegateNotif({delegateUid: target})));
    });
  }
});

describe("company notifications (nested)", () => {
  const ref = (db) => doc(db, `organizations/${ORG}/companies/${CO}/notifications/cn1`);
  test("company admin marks one read (web markAsRead$)", async () => {
    await assertSucceeds(updateDoc(ref(as("admin-a")), {read: true}));
  });
  test("company admin cannot rewrite its content", async () => {
    await assertDeniedByRule(updateDoc(ref(as("admin-a")), {message: "changed"}));
  });
  test("another company's admin cannot touch it", async () => {
    await assertDeniedByRule(updateDoc(ref(as("admin-b")), {read: true}));
  });
  test("a delegate of the company can no longer edit it", async () => {
    await assertDeniedByRule(updateDoc(ref(delegate()), {read: true}));
    await assertDeniedByRule(updateDoc(ref(delegate()), {message: "changed"}));
  });
});

describe("shared notifications are per user", () => {
  test("staff marks a shared notification read for itself (readBy)", async () => {
    await assertSucceeds(updateDoc(doc(as("hr-a"), "notifications/shared-all"), {readBy: arrayUnion("hr-a")}));
  });
  test("staff cannot mark a shared notification read for everyone", async () => {
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "notifications/shared-all"), {isRead: true}));
  });
  test("cannot add someone else to readBy / deletedBy, or remove them", async () => {
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "notifications/shared-all"), {readBy: arrayUnion("victim")}));
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "notifications/shared-all"), {readBy: []}));
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "notifications/shared-all"), {deletedBy: arrayUnion("01000000000")}));
  });
  test("staff hides a shared notification for itself (deletedBy, merge)", async () => {
    await assertSucceeds(setDoc(doc(as("hr-a"), "notifications/shared-all"), {deletedBy: arrayUnion("hr-a")}, {merge: true}));
  });
  test("delegate still marks its own notification read and hides it", async () => {
    await assertSucceeds(updateDoc(doc(delegate(), "notifications/own-del"), {readBy: arrayUnion("del-a")}));
    await assertSucceeds(updateDoc(doc(delegate(), "notifications/own-del"), {isRead: true, readAt: serverTimestamp()}));
    await assertSucceeds(setDoc(doc(delegate(), "notifications/own-del"), {deletedBy: arrayUnion("del-a")}, {merge: true}));
  });
  test("delegate cannot rewrite its own notification's content", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), "notifications/own-del"), {title: "changed"}));
  });
});
