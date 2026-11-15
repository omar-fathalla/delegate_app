/**
 * UT non-blocking fixes: org-admin badges, supervisor global notify user list,
 * org-admin today attendance sheet index query shape (rules only here).
 *
 * npx firebase-tools emulators:exec --only firestore --project demo-ut-nb \
 *   "node --test test/rules/ut-nonblocking-fixes.test.js"
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {collection, query, where, getDocs} = require("firebase/firestore");

const PROJECT_ID = "demo-ut-nb";

describe("UT non-blocking Firestore fixes", () => {
  /** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
  let env;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
    });
  });

  after(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sup").set({
        role: "supervisor",
        organizationUID: "o1",
        companyUID: "c1",
      });
      await db.doc("users/oa").set({
        role: "organization-admin",
        organizationUID: "o1",
        companyUID: "c1",
      });
      await db.doc("users/oa0").set({
        role: "organization-admin",
        organizationUID: "o1",
      });
      await db.doc("users/org2").set({
        role: "organization-admin",
        organizationUID: "o2",
        companyUID: "c9",
      });
      await db.doc("users/sa").set({role: "super-admin", organizationUID: "o1"});
      await db.doc("users/tech").set({role: "technical_support", organizationUID: "o1"});
      await db.doc("organizations/o1/companies/c1/delegates/d1").set({
        organizationUID: "o1",
        companyUID: "c1",
        nationalId: "29101010100011",
        nationalityID: "29101010100011",
        status: "active",
      });
      await db.doc("leave_requests/l-o1").set({
        organizationUID: "o1",
        companyUID: "c1",
        status: "pending",
        delegateUid: "d1",
      });
      await db.doc("leave_requests/l-o2").set({
        organizationUID: "o2",
        companyUID: "c9",
        status: "pending",
        delegateUid: "d2",
      });
      await db.doc("device_unbind_requests/u-o1").set({
        organizationUID: "o1",
        companyUID: "c1",
        status: "pending",
        delegateUid: "d1",
      });
      await db.doc("device_unbind_requests/u-o2").set({
        organizationUID: "o2",
        companyUID: "c9",
        status: "pending",
        delegateUid: "d2",
      });
      const start = new Date("2026-11-11T00:00:00.000Z");
      const mid = new Date("2026-11-11T08:00:00.000Z");
      const end = new Date("2026-11-12T00:00:00.000Z");
      await db.doc("attendance_logs/sheet1").set({
        delegateId: "d1",
        organizationId: "o1",
        companyId: "c1",
        timestamp: mid,
        type: "check_in",
      });
      await db.doc("attendance_logs/sheet2").set({
        delegateId: "d9",
        organizationId: "o2",
        companyId: "c9",
        timestamp: mid,
        type: "check_in",
      });
      await db.doc("attendance_logs/sheet-o1-c2").set({
        delegateId: "d8",
        organizationId: "o1",
        companyId: "c2",
        timestamp: mid,
        type: "check_in",
      });
      await db.doc("users/oa-c1").set({
        role: "organization-admin",
        organizationUID: "o1",
        companyUID: "c1",
      });
      // seed for cross-org deny probes
      global.__utNbTimes = {start, end};
    });
  });

  const as = (uid) =>
    env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  test("supervisor cannot list global staff users (TA-35 callable only)", async () => {
    const sup = as("sup");
    await assertFails(
      getDocs(
        query(
          collection(sup, "users"),
          where("role", "in", ["super-admin", "technical_support"]),
        ),
      ),
    );
    await assertFails(
      getDocs(query(collection(sup, "users"), where("role", "==", "delegate"))),
    );
  });

  test("supervisor duplicate chain reads stay company-scoped", async () => {
    const sup = as("sup");
    await assertSucceeds(
      getDocs(
        query(
          collection(sup, "organizations/o1/companies/c1/delegates"),
          where("nationalId", "==", "29101010100011"),
        ),
      ),
    );
    await assertSucceeds(
      getDocs(
        query(
          collection(sup, "delegate_requests"),
          where("companyUID", "==", "c1"),
          where("nationalId", "==", "29101010100011"),
          where("status", "==", "pending"),
        ),
      ),
    );
  });

  test("org-admin pending badges: own org only (with or without companyUID)", async () => {
    const oa = as("oa");
    const oa0 = as("oa0");
  const org2 = as("org2");
    const badge = (db, co) =>
      getDocs(
        query(
          collection(db, "leave_requests"),
          where("status", "==", "pending"),
          where("organizationUID", "==", "o1"),
          ...(co ? [where("companyUID", "==", co)] : []),
        ),
      );
    const badgeDevice = (db, co) =>
      getDocs(
        query(
          collection(db, "device_unbind_requests"),
          where("status", "==", "pending"),
          where("organizationUID", "==", "o1"),
          ...(co ? [where("companyUID", "==", co)] : []),
        ),
      );
    await assertSucceeds(badge(oa, "c1"));
    await assertSucceeds(badgeDevice(oa, "c1"));
    await assertSucceeds(badge(oa0, null));
    await assertSucceeds(badgeDevice(oa0, null));
    await assertFails(badge(org2, "c9"));
    await assertFails(
      getDocs(
        query(
          collection(org2, "leave_requests"),
          where("status", "==", "pending"),
          where("organizationUID", "==", "o1"),
        ),
      ),
    );
  });

  test("org-admin may read same-org other-company attendance by organizationId", async () => {
    const {start, end} = global.__utNbTimes;
    const oaC1 = as("oa-c1");
    await assertSucceeds(getDocs(
      query(
        collection(oaC1, "attendance_logs"),
        where("organizationId", "==", "o1"),
        where("companyId", "==", "c2"),
        where("timestamp", ">=", start),
        where("timestamp", "<", end),
      ),
    ));
  });

  test("org-admin today attendance sheet query shape (org + company + timestamp)", async () => {
    const {start, end} = global.__utNbTimes;
    const oa = as("oa");
    const org2 = as("org2");
    await assertSucceeds(
      getDocs(
        query(
          collection(oa, "attendance_logs"),
          where("organizationId", "==", "o1"),
          where("companyId", "==", "c1"),
          where("timestamp", ">=", start),
          where("timestamp", "<", end),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          collection(org2, "attendance_logs"),
          where("organizationId", "==", "o1"),
          where("companyId", "==", "c1"),
          where("timestamp", ">=", start),
          where("timestamp", "<", end),
        ),
      ),
    );
  });
});