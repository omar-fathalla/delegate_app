/**
 * M31 3ff8e5d: a signed-in delegate must be able to query their own
 * attendance, leave, notifications, captured photos, and delegates by
 * field uid. Another delegate's data stays denied. Project demo only.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("./_rules_testing");
const {
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} = require("firebase/firestore");

const PROJECT_ID = "demo-m31-delegate-own-reads";

const DELEGATE = {
  role: "delegate",
  delegateId: "del-1",
  delegateIds: ["del-1"],
  orgId: "o1",
  companyId: "c1",
  phones: ["01011111111"],
  firebase: {sign_in_provider: "custom"},
};

const OTHER = {
  role: "delegate",
  delegateId: "del-2",
  delegateIds: ["del-2"],
  orgId: "o1",
  companyId: "c1",
  phones: ["01022222222"],
  firebase: {sign_in_provider: "custom"},
};

describe("m31 delegate own-data queries", () => {
  let env;
  const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();

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
      await db.doc("organizations/o1/companies/c1/delegates/del-1").set({
        uid: "del-1", organizationUID: "o1", companyUID: "c1", status: "active",
        phoneNumber: "01011111111",
      });
      await db.doc("organizations/o1/companies/c1/delegates/del-2").set({
        uid: "del-2", organizationUID: "o1", companyUID: "c1", status: "active",
        phoneNumber: "01022222222",
      });
      await db.doc("attendance_logs/a1").set({
        delegateId: "del-1", organizationUID: "o1", companyUID: "c1", type: "check_in",
      });
      await db.doc("attendance_logs/a2").set({
        delegateId: "del-2", organizationUID: "o1", companyUID: "c1", type: "check_in",
      });
      await db.doc("leave_requests/l1").set({
        delegateUid: "del-1", companyUID: "c1", status: "approved",
      });
      await db.doc("leave_requests/l2").set({
        delegateUid: "del-2", companyUID: "c1", status: "approved",
      });
      await db.doc("notifications/n1").set({
        delegateUid: "del-1", phoneNumber: "01011111111", isRead: false,
      });
      await db.doc("notifications/n2").set({
        delegateUid: "del-2", phoneNumber: "01022222222", isRead: false,
      });
      await db.doc("organizations/o1/companies/c1/photo_permissions/p1/captured_photos/ph1").set({
        delegateUID: "del-1", organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("organizations/o1/companies/c1/photo_permissions/p1/captured_photos/ph2").set({
        delegateUID: "del-2", organizationUID: "o1", companyUID: "c1",
      });
    });
  });

  test("delegate can query own attendance by delegateId==uid", () =>
    assertSucceeds(getDocs(query(
      collection(as("del-1", DELEGATE), "attendance_logs"),
      where("delegateId", "==", "del-1"),
    ))));

  test("delegate cannot query attendance with a mixed whereIn that includes another id", () =>
    assertFails(getDocs(query(
      collection(as("del-1", DELEGATE), "attendance_logs"),
      where("delegateId", "in", ["del-1", "01011111111", "29901010101011"]),
    ))));

  test("delegate cannot list another delegate's attendance", () =>
    assertFails(getDocs(query(
      collection(as("del-1", DELEGATE), "attendance_logs"),
      where("delegateId", "==", "del-2"),
    ))));

  test("delegate can query own leave_requests by delegateUid", () =>
    assertSucceeds(getDocs(query(
      collection(as("del-1", DELEGATE), "leave_requests"),
      where("delegateUid", "==", "del-1"),
      where("status", "==", "approved"),
    ))));

  test("delegate cannot list another delegate's leave_requests", () =>
    assertFails(getDocs(query(
      collection(as("del-1", DELEGATE), "leave_requests"),
      where("delegateUid", "==", "del-2"),
    ))));

  // Delegate home screen listener. With a users/{uid} doc present the staff
  // read branches used to walk it three times and the query went over the
  // 1000-expression budget (permission-denied on tashil-dev, Patrol gate).
  test("delegate home leave listener (company + own uid) with users doc", async () => {
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc("users/del-1").set({
      uid: "del-1", role: "delegate", organizationUID: "o1", companyUID: "c1",
    }));
    await assertSucceeds(getDocs(query(
      collection(as("del-1", DELEGATE), "leave_requests"),
      where("companyUID", "==", "c1"),
      where("delegateUid", "==", "del-1"),
    )));
    // TAS-90: the home badge now streams pending requests only.
    await assertSucceeds(getDocs(query(
      collection(as("del-1", DELEGATE), "leave_requests"),
      where("companyUID", "==", "c1"),
      where("delegateUid", "==", "del-1"),
      where("status", "==", "pending"),
    )));
    await assertFails(getDocs(query(
      collection(as("del-1", DELEGATE), "leave_requests"),
      where("companyUID", "==", "c1"),
      where("delegateUid", "==", "del-2"),
    )));
  });

  test("delegate can query own notifications by uid and by phone claim", async () => {
    await assertSucceeds(getDocs(query(
      collection(as("del-1", DELEGATE), "notifications"),
      where("delegateUid", "==", "del-1"),
    )));
    await assertSucceeds(getDocs(query(
      collection(as("del-1", DELEGATE), "notifications"),
      where("phoneNumber", "==", "01011111111"),
    )));
  });

  test("delegate cannot list another delegate's notifications", () =>
    assertFails(getDocs(query(
      collection(as("del-1", DELEGATE), "notifications"),
      where("delegateUid", "==", "del-2"),
    ))));

  test("delegate can collectionGroup captured_photos by own delegateUID", () =>
    assertSucceeds(getDocs(query(
      collectionGroup(as("del-1", DELEGATE), "captured_photos"),
      where("delegateUID", "==", "del-1"),
    ))));

  test("delegate cannot collectionGroup captured_photos for another uid", () =>
    assertFails(getDocs(query(
      collectionGroup(as("del-1", DELEGATE), "captured_photos"),
      where("delegateUID", "==", "del-2"),
    ))));

  test("delegate can collectionGroup delegates by field uid", () =>
    assertSucceeds(getDocs(query(
      collectionGroup(as("del-1", DELEGATE), "delegates"),
      where("uid", "==", "del-1"),
    ))));

  test("delegate cannot collectionGroup delegates by another uid", () =>
    assertFails(getDocs(query(
      collectionGroup(as("del-1", DELEGATE), "delegates"),
      where("uid", "==", "del-2"),
    ))));

  test("signed-in delegate can write the time_probe field only", async () => {
    const ref = doc(as("del-1", DELEGATE), "_system_metadata/time_probe");
    await assertSucceeds(setDoc(ref, {probe: new Date()}));
    await assertFails(setDoc(ref, {probe: new Date(), extra: true}));
    await assertFails(setDoc(doc(as("del-1", DELEGATE), "_system_metadata/other"), {probe: new Date()}));
  });

  test("other delegate cannot get a different user's users doc", () =>
    assertFails(getDoc(doc(as("del-2", OTHER), "users/del-1"))));
});
