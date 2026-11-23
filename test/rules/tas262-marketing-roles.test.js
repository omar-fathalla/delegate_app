/**
 * TAS-262: the three marketing roles (marketing, marketing_promotion,
 * branches_marketing) only see their own organization, and the reads their
 * screens make are allowed.
 *  - TAS-265: today's attendance of the org's branches (organizationId +
 *    branchName in + timestamp range), the query the Branches tab sends.
 *  - TAS-266: a branches-marketing manager with no companyUID is org-wide
 *    (penalties, tasks, delegates, photo permissions); with a companyUID it
 *    stays on its company.
 *  - TAS-269: role broadcast notifications for each role.
 * Fake data only.
 *
 * npm run test:rules:tas262
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertFails} = require("./_rules_testing");
const {collection, collectionGroup, doc, getDoc, getDocs, query, setDoc, Timestamp, updateDoc, where} =
  require("firebase/firestore");

const ORG = "seed-fake-org-fth";
const OTHER = "seed-fake-org-other";
const CO_A = "seed-fake-co-a";
const CO_B = "seed-fake-co-b";
const STAFF = {firebase: {sign_in_provider: "password"}};

const users = {
  mk: {role: "marketing", organizationUID: ORG},
  pr: {role: "marketing_promotion", organizationUID: ORG},
  bmm: {role: "branches_marketing", organizationUID: ORG},
  bmmc: {role: "branches_marketing", organizationUID: ORG, companyUID: CO_A},
};

let env;
const as = (uid) => env.authenticatedContext(uid, STAFF).firestore();
const dayStart = () => {
  const d = new Date();
  return Timestamp.fromDate(new Date(d.getFullYear(), d.getMonth(), d.getDate()));
};
const dayEnd = () => Timestamp.fromMillis(dayStart().toMillis() + 864e5);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas262",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true, email: `${uid}@example.com`});
    }
    for (const [org, co, tag] of [[ORG, CO_A, "a"], [ORG, CO_B, "b"], [OTHER, "seed-fake-co-x", "x"]]) {
      await setDoc(doc(db, `attendance_logs/att-${tag}`), {
        organizationId: org, organizationUID: org, companyId: co, companyUID: co,
        branchName: `branch-${tag}`, delegateId: `del-${tag}`, type: "check_in",
        timestamp: Timestamp.fromMillis(dayStart().toMillis() + 3600e3),
      });
      await setDoc(doc(db, `penalties/pen-${tag}`), {
        organizationId: org, organizationUID: org, companyId: co, companyUID: co,
        status: "PENDING_BRANCHES_MARKETING", fineAmount: 200, targetDelegateId: `del-${tag}`,
      });
      await setDoc(doc(db, `organizations/${org}/companies/${co}/delegates/del-${tag}`), {
        uid: `del-${tag}`, organizationUID: org, companyUID: co, phoneNumber: `0100000000${tag}`,
      });
      await setDoc(doc(db, `organizations/${org}/companies/${co}/photo_permissions/pp-${tag}`), {
        organizationUID: org, companyUID: co, status: "pending", createdAt: Timestamp.now(),
      });
      await setDoc(doc(db, `organizations/${org}/tasks/task-${tag}`), {
        organizationId: org, companyId: co, assignedTo: "all_branch_marketing", status: "pending",
      });
    }
    for (const r of ["marketing", "branchesMarketingManager", "all"]) {
      await setDoc(doc(db, `notifications/n-${r}`), {delegateUid: r, title: "fake"});
    }
  });
});

after(async () => env && env.cleanup());

const attendanceQuery = (db, org, branches) => query(collection(db, "attendance_logs"),
  where("organizationId", "==", org),
  where("branchName", "in", branches),
  where("timestamp", ">=", dayStart()),
  where("timestamp", "<", dayEnd()));

describe("TAS-265 attendance of the org's branches", () => {
  for (const uid of ["mk", "pr", "bmm"]) {
    test(`${uid} reads today's attendance of its org`, async () => {
      const snap = await assertSucceeds(getDocs(attendanceQuery(as(uid), ORG, ["branch-a", "branch-b"])));
      if (snap.size !== 2) throw new Error(`expected 2, got ${snap.size}`);
    });
    test(`${uid} cannot read another org's attendance`, async () => {
      await assertFails(getDocs(attendanceQuery(as(uid), OTHER, ["branch-x"])));
      await assertFails(getDoc(doc(as(uid), "attendance_logs/att-x")));
    });
  }
  test("company-scoped branches marketing does not get the org-wide read", async () => {
    await assertFails(getDocs(attendanceQuery(as("bmmc"), ORG, ["branch-a", "branch-b"])));
  });
});

describe("TAS-266 org-wide branches marketing manager", () => {
  test("lists and decides penalties of its org", async () => {
    const db = as("bmm");
    await assertSucceeds(getDocs(query(collection(db, "penalties"), where("organizationId", "==", ORG))));
    await assertSucceeds(getDoc(doc(db, "penalties/pen-b")));
    await assertSucceeds(updateDoc(doc(db, "penalties/pen-a"), {status: "PENDING_HR"}));
  });
  test("cannot read or decide another org's penalties", async () => {
    const db = as("bmm");
    await assertFails(getDocs(query(collection(db, "penalties"), where("organizationId", "==", OTHER))));
    await assertFails(getDoc(doc(db, "penalties/pen-x")));
    await assertFails(updateDoc(doc(db, "penalties/pen-x"), {status: "PENDING_HR"}));
  });
  test("reads tasks of its org, not another org", async () => {
    await assertSucceeds(getDocs(collection(as("bmm"), `organizations/${ORG}/tasks`)));
    await assertFails(getDocs(collection(as("bmm"), `organizations/${OTHER}/tasks`)));
  });
  test("searches delegates of its org, not another org", async () => {
    await assertSucceeds(getDocs(query(collectionGroup(as("bmm"), "delegates"), where("organizationUID", "==", ORG))));
    await assertFails(getDocs(query(collectionGroup(as("bmm"), "delegates"), where("organizationUID", "==", OTHER))));
  });
  test("photo permissions report of its org", async () => {
    await assertSucceeds(getDocs(query(collectionGroup(as("bmm"), "photo_permissions"), where("organizationUID", "==", ORG))));
    await assertFails(getDocs(query(collectionGroup(as("bmm"), "photo_permissions"), where("organizationUID", "==", OTHER))));
  });
  test("with a companyUID it stays on its company", async () => {
    const db = as("bmmc");
    await assertSucceeds(getDocs(query(collection(db, "penalties"), where("companyId", "==", CO_A))));
    await assertFails(getDocs(query(collection(db, "penalties"), where("organizationId", "==", ORG))));
    await assertFails(getDoc(doc(db, "penalties/pen-b")));
    await assertFails(getDocs(query(collectionGroup(db, "delegates"), where("organizationUID", "==", ORG))));
  });
});

describe("TAS-269 role broadcast notifications", () => {
  const q = (db, r) => getDocs(query(collection(db, "notifications"), where("delegateUid", "==", r)));
  test("marketing roles read the marketing broadcast", async () => {
    await assertSucceeds(q(as("mk"), "marketing"));
    await assertSucceeds(q(as("pr"), "marketing"));
  });
  test("all three read the app-wide broadcast", async () => {
    for (const uid of ["mk", "pr", "bmm"]) await assertSucceeds(q(as(uid), "all"));
  });
  test("branches marketing reads its broadcast", async () => {
    await assertSucceeds(q(as("bmm"), "branchesMarketingManager"));
    await assertSucceeds(q(as("bmmc"), "branchesMarketingManager"));
  });
  // Still denied by canReadNotification's 1000-expression budget, not by a
  // rule (pre-existing; baseline 2). Follow-up sub-issue under TAS-269.
  test("roles do not read each other's broadcast", async () => {
    await assertFails(q(as("mk"), "branchesMarketingManager"));
    await assertFails(q(as("bmm"), "marketing"));
  });
});

describe("TAS-268 sent notifications log for branches marketing", () => {
  test("logs and reads only its own sends", async () => {
    const db = as("bmm");
    await assertSucceeds(setDoc(doc(db, "sent_notifications/s-bmm"), {senderUid: "bmm", title: "fake", createdAt: Timestamp.now()}));
    await assertSucceeds(getDocs(query(collection(db, "sent_notifications"), where("senderUid", "==", "bmm"))));
    await assertFails(setDoc(doc(db, "sent_notifications/s-forged"), {senderUid: "someone-else", title: "fake"}));
    await assertFails(getDocs(collection(db, "sent_notifications")));
  });
});

describe("TAS-266 follow-up notifications after a penalty decision", () => {
  const payload = (by) => ({title: "fake", type: "penalty", penaltyId: "pen-a", companyId: CO_A,
    delegateUid: "company_" + CO_A, isRead: false, ...(by ? {createdBy: by} : {})});
  test("org-wide manager sends them stamped with its uid", async () => {
    await assertSucceeds(setDoc(doc(as("bmm"), "notifications/n-dec-1"), payload("bmm")));
  });
  // Denied, but by canCreateNotification's budget (baseline +2), TAS-291.
  test("not without createdBy, and not as someone else", async () => {
    await assertFails(setDoc(doc(as("bmm"), "notifications/n-dec-2"), payload(null)));
    await assertFails(setDoc(doc(as("bmm"), "notifications/n-dec-3"), payload("someone-else")));
  });
});

describe("TAS-268 manager sends by role / by phone inside its org", () => {
  test("lists users of its org by role and by phone", async () => {
    const db = as("bmm");
    await assertSucceeds(getDocs(query(collection(db, "users"),
      where("role", "==", "marketing"), where("organizationUID", "==", ORG))));
    await assertSucceeds(getDocs(query(collection(db, "users"),
      where("phoneNumber", "==", "01000000901"), where("organizationUID", "==", ORG))));
    await assertSucceeds(getDocs(query(collectionGroup(db, "delegates"),
      where("phoneNumber", "==", "0100000000a"), where("organizationUID", "==", ORG))));
  });
  // These two are denied by the old users list rule's budget (TAS-291).
  test("not another org's users, and not an unscoped list", async () => {
    const db = as("bmm");
    await assertFails(getDocs(query(collection(db, "users"),
      where("role", "==", "marketing"), where("organizationUID", "==", OTHER))));
    await assertFails(getDocs(query(collection(db, "users"), where("role", "==", "marketing"))));
  });
  test("a company-scoped manager does not get the org-wide list", async () => {
    await assertFails(getDocs(query(collection(as("bmmc"), "users"),
      where("role", "==", "marketing"), where("organizationUID", "==", ORG))));
  });
});
