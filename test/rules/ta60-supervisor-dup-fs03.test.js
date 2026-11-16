/**
 * FS-03..06 / FS-09 / FS-10: supervisor company-scoped dup listens + narrow suspend.
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  collectionGroup,
  doc,
  getDocs,
  query,
  updateDoc,
  where,
  limit,
  serverTimestamp,
} = require("firebase/firestore");

const PROJECT = "demo-ta60-supervisor-dup-fs03";
const ORG = "orgA";
const CO = "coA";
const CO2 = "coB";
const D = (o, c, id) => `organizations/${o}/companies/${c}/delegates/${id}`;

describe("ta60 supervisor dup + FS-09", () => {
  let env;
  const staff = (uid, extra = {}) =>
    env.authenticatedContext(uid, {
      email: `${uid}@t.test`,
      email_verified: true,
      firebase: {sign_in_provider: "password"},
      ...extra,
    }).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT,
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore();
      await db.doc(`organizations/${ORG}`).set({name: "orgA", status: "active"});
      await db.doc(`organizations/${ORG}/companies/${CO}`).set({
        name: "coA", organizationUID: ORG, status: "Active",
      });
      await db.doc(`organizations/${ORG}/companies/${CO2}`).set({
        name: "coB", organizationUID: ORG, status: "Active",
      });
      await db.doc("users/sup").set({
        uid: "sup", role: "supervisor", organizationUID: ORG, companyUID: CO,
      });
      await db.doc("users/hr").set({
        uid: "hr", role: "hr", organizationUID: ORG, companyUID: CO,
      });
      await db.doc(D(ORG, CO, "dlg1")).set({
        uid: "dlg1", organizationUID: ORG, companyUID: CO, status: "active",
        phoneNumber: "01000000001", nationalId: "29001010101010",
        nationalityID: "29001010101010", receiptCode: "R-dlg1",
      });
      await db.doc(D(ORG, CO2, "dlg2")).set({
        uid: "dlg2", organizationUID: ORG, companyUID: CO2, status: "active",
        phoneNumber: "01000000002", nationalId: "29002020202020",
        nationalityID: "29002020202020", receiptCode: "R-dlg2",
      });
      await db.doc("delegate_requests/req1").set({
        id: "req1", supervisorUid: "sup", companyUID: CO, organizationUID: ORG,
        status: "pending", receiptCode: "RC1",
      });
    });
  });

  test("FS-03 ALLOW supervisor CG phoneNumber dup same company", () =>
    assertSucceeds(getDocs(query(
      collectionGroup(staff("sup"), "delegates"),
      where("phoneNumber", "==", "01000000001"),
      limit(1),
    ))));

  test("FS-04 ALLOW supervisor CG nationalId dup same company", () =>
    assertSucceeds(getDocs(query(
      collectionGroup(staff("sup"), "delegates"),
      where("nationalId", "==", "29001010101010"),
      limit(1),
    ))));

  test("FS-10 ALLOW supervisor registration nationalId listen", () =>
    assertSucceeds(getDocs(query(
      collectionGroup(staff("sup"), "delegates"),
      where("nationalId", "==", "29009090909090"),
      limit(1),
    ))));

  test("FS-05 ALLOW supervisor CG receiptCode dup same company", () =>
    assertSucceeds(getDocs(query(
      collectionGroup(staff("sup"), "delegates"),
      where("receiptCode", "==", "R-dlg1"),
      limit(1),
    ))));

  test("FS-06 ALLOW supervisor delegate_requests receiptCode same company", () =>
    assertSucceeds(getDocs(query(
      collection(staff("sup"), "delegate_requests"),
      where("companyUID", "==", CO),
      where("receiptCode", "==", "RC1"),
    ))));

  test("FS-09 ALLOW supervisor suspend same company", () =>
    assertSucceeds(updateDoc(doc(staff("sup"), D(ORG, CO, "dlg1")), {
      status: "suspended",
      statusReason: "suspend",
      updatedAt: serverTimestamp(),
    })));

  test("FS-09 DENY supervisor suspend without statusReason", () =>
    assertFails(updateDoc(doc(staff("sup"), D(ORG, CO, "dlg1")), {
      status: "suspended",
      updatedAt: serverTimestamp(),
    })));

  test("FS-09 DENY supervisor suspend other company delegate", () =>
    assertFails(updateDoc(doc(staff("sup"), D(ORG, CO2, "dlg2")), {
      status: "suspended",
      statusReason: "suspend",
      updatedAt: serverTimestamp(),
    })));

  test("FS-09 DENY HR suspend delegate", () =>
    assertFails(updateDoc(doc(staff("hr"), D(ORG, CO, "dlg1")), {
      status: "suspended",
      statusReason: "suspend",
      updatedAt: serverTimestamp(),
    })));

  test("FS-09 DENY supervisor pending→active via status write", async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await c.firestore().doc(D(ORG, CO, "dlg1")).set({
        uid: "dlg1", organizationUID: ORG, companyUID: CO, status: "pending",
      });
    });
    await assertFails(updateDoc(doc(staff("sup"), D(ORG, CO, "dlg1")), {
      status: "active",
      statusReason: "x",
      updatedAt: serverTimestamp(),
    }));
  });
});