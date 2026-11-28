/**
 * TAS-5 High gaps in the rules (TAS-43, 44, 45, 46, 47, 48, 50, 52).
 * Each block has the app/web write that must keep working and the attack
 * that must be denied by a rule (assertDeniedByRule: never by the
 * 1000-expression budget). Write shapes mirror the client code.
 * Fake data only.
 *
 * npm run test:rules:tas5-high
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp, runTransaction} = require("firebase/firestore");

const ORG_A = "seed-fake-tas5-org-a";
const ORG_B = "seed-fake-tas5-org-b";
const CO_A = "seed-fake-tas5-co-a";
const CO_A2 = "seed-fake-tas5-co-a2";
const CO_B = "seed-fake-tas5-co-b";

const staff = {
  "sa": {role: "super-admin"},
  "orgadmin-a": {role: "organization-admin", organizationUID: ORG_A},
  "admin-a": {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A},
  "hr-a": {role: "hr", organizationUID: ORG_A, companyUID: CO_A},
  "acc-a": {role: "accountant", organizationUID: ORG_A, companyUID: CO_A},
  "bm-a": {role: "branches_marketing", organizationUID: ORG_A, companyUID: CO_A},
  "admin-b": {role: "company-admin", organizationUID: ORG_B, companyUID: CO_B},
  "tech": {role: "technical_support"},
};

let env;

const ts = (iso) => Timestamp.fromDate(new Date(iso));

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas5-high",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) {
      await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    }
    await setDoc(doc(db, `users/del-a`), {role: "delegate", organizationUID: ORG_A, companyUID: CO_A, fake: true});
    await setDoc(doc(db, `users/victim`), {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A, fake: true});
    for (const [org, co] of [[ORG_A, CO_A], [ORG_A, CO_A2], [ORG_B, CO_B]]) {
      await setDoc(doc(db, `organizations/${org}`), {name: org, fake: true});
      await setDoc(doc(db, `organizations/${org}/companies/${co}`), {name: co, organizationUID: org, fake: true});
      await setDoc(doc(db, `organizations/${org}/companies/${co}/requests/req-1`), {
        status: "pending", companyUID: co, organizationUID: org, fake: true,
      });
    }
    // leave
    await setDoc(doc(db, "leave_requests/leave-pending"), {
      delegateUid: "del-a", companyUID: CO_A, organizationUID: ORG_A, status: "pending", fake: true,
    });
    await setDoc(doc(db, "leave_requests/leave-pending-b"), {
      delegateUid: "del-b", companyUID: CO_B, organizationUID: ORG_B, status: "pending", fake: true,
    });
    // wallet
    await setDoc(doc(db, "user_wallets/del-a"), {
      userId: "del-a", companyUID: CO_A, currentBalance: 100, totalPaid: 0, fake: true,
    });
    // attendance
    await setDoc(doc(db, "attendance_logs/in-a"), {
      delegateId: "del-a", userId: "del-a", companyId: CO_A, organizationId: ORG_A,
      type: "check_in", timestamp: ts("2026-11-23T07:00:00Z"), fake: true,
    });
    await setDoc(doc(db, "attendance_logs/in-a-old"), {
      delegateId: "del-a", userId: "del-a", companyId: CO_A, organizationId: ORG_A,
      type: "check_in", timestamp: ts("2026-11-20T07:00:00Z"), fake: true,
    });
    await setDoc(doc(db, "_system_metadata/time_probe"), {probe: ts("2026-11-23T07:00:00Z")});
    // penalties
    await setDoc(doc(db, "penalties/pen-a"), {
      companyId: CO_A, organizationId: ORG_A, status: "PENDING_BRANCHES_MARKETING", title: "t", fake: true,
    });
    await setDoc(doc(db, "penalties/pen-a2"), {
      companyId: CO_A2, organizationId: ORG_A, status: "PENDING_BRANCHES_MARKETING", title: "t", fake: true,
    });
    await setDoc(doc(db, "penalties/pen-b"), {
      companyId: CO_B, organizationId: ORG_B, status: "PENDING_BRANCHES_MARKETING", title: "t", fake: true,
    });
    // tasks
    const task = (over) => ({
      title: "Fake task", description: "d", priority: "normal", status: "pending",
      assignedTo: "all", assignedToName: "الكل", companyId: CO_A, createdBy: "admin-a",
      createdByName: "Admin", dueDate: null, createdAt: ts("2026-11-23T06:00:00Z"),
      completedAt: null, completedBy: null, notes: null, fake: true, ...over,
    });
    await setDoc(doc(db, `organizations/${ORG_A}/tasks/task-all`), task());
    await setDoc(doc(db, `organizations/${ORG_A}/tasks/task-all-other-co`), task({companyId: CO_A2}));
    await setDoc(doc(db, `organizations/${ORG_A}/tasks/task-own`), task({assignedTo: "del-a", companyId: CO_A2}));
    await setDoc(doc(db, "counters/delegates"), {count: 7000});
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const delegate = (uid = "del-a", org = ORG_A, co = CO_A) => env.authenticatedContext(uid, {
  role: "delegate", orgId: org, companyId: co, delegateId: uid,
}).firestore();

describe("TAS-44: collection-group companies write is gone", () => {
  test("org admin of chain A cannot write a company of chain B", async () => {
    await assertDeniedByRule(updateDoc(doc(as("orgadmin-a"), `organizations/${ORG_B}/companies/${CO_B}`), {name: "x"}));
    await assertDeniedByRule(setDoc(doc(as("orgadmin-a"), `organizations/${ORG_B}/companies/new-co`), {name: "x"}));
  });
  test("company staff cannot put its own company id under another chain", async () => {
    await assertDeniedByRule(setDoc(doc(as("admin-a"), `organizations/${ORG_B}/companies/${CO_A}`), {name: "x"}));
  });
  test("org admin still edits its own chain's companies (web updateCompanyName$)", async () => {
    await assertSucceeds(updateDoc(doc(as("orgadmin-a"), `organizations/${ORG_A}/companies/${CO_A}`), {
      name: "Renamed", updatedAt: serverTimestamp(),
    }));
  });
  test("company admin still updates its own company documents (web updateCompanyDocuments$)", async () => {
    await assertSucceeds(updateDoc(doc(as("admin-a"), `organizations/${ORG_A}/companies/${CO_A}`), {
      commercialRegisterNumber: "123", updatedAt: serverTimestamp(),
    }));
  });
});

describe("TAS-45: collection-group requests write is gone", () => {
  test("company B staff cannot overwrite company A's request by claiming the company", async () => {
    await assertDeniedByRule(setDoc(doc(as("admin-b"), `organizations/${ORG_A}/companies/${CO_A}/requests/req-1`), {
      status: "approved", companyUID: CO_B, organizationUID: ORG_B,
    }));
  });
  test("company admin still files a request in its own company (web delegate-request.service)", async () => {
    await assertSucceeds(setDoc(doc(as("admin-a"), `organizations/${ORG_A}/companies/${CO_A}/requests/req-new`), {
      actionType: "create", status: "pending", companyUID: CO_A, organizationUID: ORG_A, fake: true,
    }));
  });
});

describe("TAS-46: leave_requests", () => {
  const leave = (over) => ({
    id: "x", delegateUid: "del-a", delegateName: "Fake", delegatePhone: "01000000000",
    companyUID: CO_A, organizationUID: ORG_A, type: "annual", isHourly: false, hoursCount: null,
    startDate: Timestamp.fromMillis(Date.now() + 86400000), endDate: Timestamp.fromMillis(Date.now() + 2 * 86400000), daysCount: 2,
    reason: "r", attachmentUrl: null, createdAt: serverTimestamp(), status: "pending",
    resolvedAt: null, resolvedBy: null, resolvedByName: null, rejectReason: null, ...over,
  });
  test("delegate files a pending request (app shape)", async () => {
    await assertSucceeds(setDoc(doc(delegate(), "leave_requests/l-new"), leave()));
  });
  test("delegate cannot file it already approved", async () => {
    await assertDeniedByRule(setDoc(doc(delegate(), "leave_requests/l-approved"), leave({status: "approved"})));
    await assertDeniedByRule(setDoc(doc(delegate(), "leave_requests/l-resolved"), leave({resolvedBy: "del-a"})));
  });
  test("delegate cannot approve its own pending request", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), "leave_requests/leave-pending"), {status: "approved"}));
  });
  test("delegate still cancels (deletes) its own pending request", async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), "leave_requests/leave-cancel"), {
      delegateUid: "del-a", companyUID: CO_A, status: "pending",
    }));
    await assertSucceeds(deleteDoc(doc(delegate(), "leave_requests/leave-cancel")));
  });
  test("HR approves a request of its company", async () => {
    await assertSucceeds(updateDoc(doc(as("hr-a"), "leave_requests/leave-pending"), {
      status: "approved", resolvedAt: serverTimestamp(), resolvedBy: "hr-a", resolvedByName: "HR",
    }));
  });
  test("HR cannot touch another company's request or move one out", async () => {
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "leave_requests/leave-pending-b"), {status: "approved"}));
  });
  test("HR still creates an approved leave for a delegate of its company", async () => {
    await assertSucceeds(setDoc(doc(as("hr-a"), "leave_requests/l-hr"), leave({
      status: "approved", resolvedAt: serverTimestamp(), resolvedBy: "hr-a", resolvedByName: "HR",
    })));
  });
});

describe("TAS-47: user_wallets", () => {
  test("owner reads its wallet", async () => {
    const {getDoc} = require("firebase/firestore");
    await assertSucceeds(getDoc(doc(delegate(), "user_wallets/del-a")));
  });
  test("owner cannot change its balance or company", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), "user_wallets/del-a"), {currentBalance: 999999}));
    await assertDeniedByRule(updateDoc(doc(delegate(), "user_wallets/del-a"), {companyUID: CO_B}));
  });
  test("owner cannot write its ledger", async () => {
    await assertDeniedByRule(setDoc(doc(delegate(), "user_wallets/del-a/transactions/t1"), {
      userId: "del-a", type: "payout", amount: -1,
    }));
  });
  test("super admin still adjusts the balance with a ledger entry (wallet_remote_data_source)", async () => {
    const db = as("sa");
    await assertSucceeds(runTransaction(db, async (tx) => {
      tx.update(doc(db, "user_wallets/del-a"), {currentBalance: 150, updatedAt: serverTimestamp(), updatedBy: "sa"});
      tx.set(doc(db, "user_wallets/del-a/transactions/t-sa"), {
        userId: "del-a", type: "adjustment", amount: 50, balanceBefore: 100, balanceAfter: 150,
        notes: "", createdBy: "sa", createdByName: "SA", createdAt: serverTimestamp(),
      });
    }));
  });
});

describe("TAS-48: attendance", () => {
  const checkIn = (over) => ({
    delegateId: "del-a", userId: "del-a", companyId: CO_A, organizationId: ORG_A,
    timestamp: serverTimestamp(), type: "check_in", location: {latitude: 30, longitude: 31},
    deviceInfo: "fake", branchName: "Fake Branch", ...over,
  });
  test("delegate checks in with the server time (app shape)", async () => {
    await assertSucceeds(setDoc(doc(delegate(), "attendance_logs/new-in"), checkIn()));
  });
  test("delegate cannot check in with a chosen time", async () => {
    await assertDeniedByRule(setDoc(doc(delegate(), "attendance_logs/forged-in"),
      checkIn({timestamp: ts("2026-11-23T06:00:00Z")})));
  });
  test("delegate cannot create a manually-adjusted record", async () => {
    await assertDeniedByRule(setDoc(doc(delegate(), "attendance_logs/forged-adj"),
      checkIn({isManuallyAdjusted: true})));
  });
  test("delegate checks out (batch: _out doc + check-in update, server time)", async () => {
    await assertSucceeds(setDoc(doc(delegate(), "attendance_logs/in-a_out"), {
      delegateId: "del-a", userId: "del-a", companyId: CO_A, organizationId: ORG_A,
      timestamp: serverTimestamp(), type: "check_out", location: {latitude: 30, longitude: 31},
      relatedCheckInId: "in-a",
    }));
    await assertSucceeds(updateDoc(doc(delegate(), "attendance_logs/in-a"), {
      checkOutTime: serverTimestamp(), checkOutLocation: {latitude: 30, longitude: 31}, checkOutDocId: "in-a_out",
    }));
  });
  test("delegate auto-closes an expired session with a past time", async () => {
    const out = ts("2026-11-20T18:30:00Z");
    await assertSucceeds(setDoc(doc(delegate(), "attendance_logs/auto-out"), {
      delegateId: "del-a", userId: "del-a", companyId: CO_A, organizationId: ORG_A,
      timestamp: out, type: "check_out", location: {latitude: 30, longitude: 31},
      relatedCheckInId: "in-a-old", isAutoCheckOut: true, autoCheckOutReason: "expired",
    }));
    await assertSucceeds(updateDoc(doc(delegate(), "attendance_logs/in-a-old"), {
      checkOutTime: out, checkOutLocation: {latitude: 30, longitude: 31}, checkOutDocId: "auto-out",
      isAutoCheckOut: true, autoCheckOutReason: "expired",
    }));
  });
  test("delegate cannot move its check-in time, chain or status", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), "attendance_logs/in-a"), {timestamp: ts("2026-11-23T05:00:00Z")}));
    await assertDeniedByRule(updateDoc(doc(delegate(), "attendance_logs/in-a"), {organizationId: ORG_B}));
    await assertDeniedByRule(updateDoc(doc(delegate(), "attendance_logs/in-a"), {type: "check_out"}));
  });
  test("delegate cannot pick a future check-out time", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), "attendance_logs/in-a"), {
      checkOutTime: ts("2030-01-01T00:00:00Z"), isAutoCheckOut: true,
    }));
  });
  test("HR adjusts a record of its company (hr_delegate_attendance_detail_screen)", async () => {
    await assertSucceeds(updateDoc(doc(as("hr-a"), "attendance_logs/in-a"), {
      timestamp: ts("2026-11-23T06:45:00Z"), isManuallyAdjusted: true, lastAdjustedBy: "HR",
      lastAdjustedAt: serverTimestamp(), adjustmentReason: "fake",
    }));
  });
  test("HR cannot move a record to another company", async () => {
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), "attendance_logs/in-a"), {companyId: CO_B}));
  });
  test("HR still creates a manual check-out for a delegate", async () => {
    await assertSucceeds(setDoc(doc(as("hr-a"), "attendance_logs/hr-out"), {
      delegateId: "del-a", userId: "del-a", companyId: CO_A, organizationId: ORG_A,
      timestamp: ts("2026-11-23T15:00:00Z"), type: "check_out", relatedCheckInId: "in-a",
      deviceInfo: "تسجيل يدوي بواسطة الموارد البشرية", isManuallyAdjusted: true,
    }));
  });
  test("time probe takes only the server time", async () => {
    await assertSucceeds(setDoc(doc(delegate(), "_system_metadata/time_probe"), {probe: serverTimestamp()}, {merge: true}));
    await assertDeniedByRule(setDoc(doc(delegate(), "_system_metadata/time_probe"), {probe: ts("2030-01-01T00:00:00Z")}));
  });
});

describe("TAS-50: penalties stay in their company", () => {
  test("company admin cannot pull another company's penalty into its own", async () => {
    await assertDeniedByRule(updateDoc(doc(as("bm-a"), "penalties/pen-b"), {companyId: CO_A, organizationId: ORG_A}));
  });
  test("company staff cannot push its penalty to another company", async () => {
    await assertDeniedByRule(updateDoc(doc(as("bm-a"), "penalties/pen-a"), {companyId: CO_B, organizationId: ORG_B}));
    await assertDeniedByRule(updateDoc(doc(as("bm-a"), "penalties/pen-a"), {companyId: CO_A2}));
  });
  test("branches marketing still approves a penalty of its company", async () => {
    await assertSucceeds(updateDoc(doc(as("bm-a"), "penalties/pen-a"), {
      status: "PENDING_GENERAL_MANAGER", updatedAt: serverTimestamp(),
    }));
  });
  test("org admin may move a penalty between companies of its own chain", async () => {
    await assertSucceeds(updateDoc(doc(as("orgadmin-a"), "penalties/pen-a2"), {companyId: CO_A}));
  });
});

describe("TAS-52: tasks", () => {
  const path = (id) => `organizations/${ORG_A}/tasks/${id}`;
  test("delegate cannot make itself the sender of an 'all' task", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), path("task-all")), {createdBy: "del-a"}));
  });
  test("delegate cannot edit the title of an 'all' task", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), path("task-all")), {title: "hacked"}));
  });
  test("delegate cannot act on an 'all' task of another company in the chain", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), path("task-all-other-co")), {status: "completed"}));
  });
  test("delegate completes an 'all' task (updateTaskStatus)", async () => {
    await assertSucceeds(updateDoc(doc(delegate(), path("task-all")), {
      status: "completed", completedAt: serverTimestamp(),
    }));
  });
  test("delegate saves its own task from details (updateTask sends the whole doc)", async () => {
    await assertSucceeds(setDoc(doc(delegate(), path("task-own")), {
      title: "Fake task", description: "d", priority: "normal", status: "inProgress",
      assignedTo: "del-a", assignedToName: "الكل", companyId: CO_A2, createdBy: "admin-a",
      createdByName: "Admin", dueDate: null, createdAt: ts("2026-11-23T06:00:00Z"),
      completedAt: null, completedBy: null, notes: "on it", fake: true,
    }));
  });
  test("company admin cannot take over another sender's task", async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path("task-by-hr")), {
      title: "t", status: "pending", assignedTo: "all", companyId: CO_A, createdBy: "hr-a",
    }));
    await assertDeniedByRule(updateDoc(doc(as("admin-a"), path("task-by-hr")), {createdBy: "admin-a"}));
  });
});

describe("TAS-43: role spelling and the counter", () => {
  test("org admin cannot give a staff user a super-admin role spelled differently", async () => {
    for (const role of ["SUPER-ADMIN", "Super_Admin ", "super admin", "Technical Support"]) {
      await assertDeniedByRule(updateDoc(doc(as("orgadmin-a"), "users/victim"), {role}));
    }
  });
  test("org admin still sets an ordinary staff role in its chain", async () => {
    await assertSucceeds(updateDoc(doc(as("orgadmin-a"), "users/victim"), {role: "hr"}));
  });
  test("counter only goes up by one (delegatePublicId transaction)", async () => {
    const db = as("admin-a");
    await assertSucceeds(setDoc(doc(db, "counters/delegates"), {count: 7001}, {merge: true}));
    await assertDeniedByRule(setDoc(doc(db, "counters/delegates"), {count: 1}, {merge: true}));
    await assertDeniedByRule(setDoc(doc(db, "counters/delegates"), {count: 9000}, {merge: true}));
    await assertDeniedByRule(deleteDoc(doc(db, "counters/delegates")));
  });
});
