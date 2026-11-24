/**
 * TAS-5 Medium gaps (TAS-53, 54, 56, 57, 58, 59, 60). Each block keeps the
 * app / web write that must still work and denies the attack by a rule
 * (never the 1000-expression budget). Write shapes mirror the clients.
 * Fake data only.
 *
 * npm run test:rules:tas5-medium
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertSucceeds, assertDeniedByRule} = require("./_rules_testing");
const {doc, setDoc, updateDoc, deleteDoc, getDoc, serverTimestamp, increment} = require("firebase/firestore");

const ORG = "seed-fake-tas5m-org";
const ORG_B = "seed-fake-tas5m-org-b";
const CO = "seed-fake-tas5m-co";
const CO_B = "seed-fake-tas5m-co-b";

const staff = {
  "sa": {role: "super-admin"},
  "tech": {role: "technical_support"},
  "orgadmin": {role: "organization-admin", organizationUID: ORG},
  "orgadmin-invite": {role: "org-admin", organizationUID: ORG},
  "admin-a": {role: "company-admin", organizationUID: ORG, companyUID: CO},
  "hr-a": {role: "hr", organizationUID: ORG, companyUID: CO},
  "acc-a": {role: "accountant", organizationUID: ORG, companyUID: CO},
  "bm-a": {role: "branches_marketing", organizationUID: ORG, companyUID: CO},
  "admin-b": {role: "company-admin", organizationUID: ORG, companyUID: CO_B},
  "mkt": {role: "marketing", organizationUID: ORG},
};

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas5-medium",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, u] of Object.entries(staff)) await setDoc(doc(db, `users/${uid}`), {...u, fake: true});
    await setDoc(doc(db, `organizations/${ORG}`), {name: "Fake", fake: true});
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}`), {name: "Fake A", deferredPayment: 0, fake: true});
    await setDoc(doc(db, "branches/br-a"), {branchName: "Fake A", organizationUID: ORG, geofenceRadius: 100, fake: true});
    await setDoc(doc(db, "branches/br-b"), {branchName: "Fake B", organizationUID: ORG_B, geofenceRadius: 100, fake: true});
    await setDoc(doc(db, `organizations/${ORG}/branches/br-a`), {branchName: "Fake A", geofenceRadius: 100, fake: true});
    await setDoc(doc(db, "security_audit_logs/log-a"), {companyUID: CO, organizationUID: ORG, delegateUid: "d1", status: "blocked", fake: true});
    await setDoc(doc(db, "used_receipt_codes/RC-A"), {companyUID: CO, organizationUID: ORG, status: "reserved", fake: true});
    await setDoc(doc(db, "used_receipt_codes/RC-B"), {companyUID: CO_B, organizationUID: ORG, status: "reserved", fake: true});
    await setDoc(doc(db, "monthly_collections/2026-11"), {grandTotalDue: 0, fake: true});
    await setDoc(doc(db, "floor_checks/2026-11-24_br_d2"), {delegateId: "d2", branchName: "br", status: "ok", fake: true});
    await setDoc(doc(db, "sent_notifications/s-other"), {senderUid: "someone", title: "x", fake: true});
    await setDoc(doc(db, "sent_notifications/s-own"), {senderUid: "hr-a", title: "x", fake: true});
    await setDoc(doc(db, `organizations/${ORG}/companyRequests/cr-b`), {targetCompanyId: CO_B, status: "pending", fake: true});
    await setDoc(doc(db, `organizations/${ORG}/private_label_audits/au-1`), {delegateUid: "d1", reviewStatus: "pending", fake: true});
    await setDoc(doc(db, `organizations/${ORG}/private_label_days/d2_2026-11-24`), {delegateUid: "d2", auditsCount: 1, fake: true});
  });
});

after(async () => env && env.cleanup());

const as = (uid) => env.authenticatedContext(uid).firestore();
const delegate = (uid = "d1") => env.authenticatedContext(uid, {
  role: "delegate", orgId: ORG, companyId: CO, delegateId: uid,
}).firestore();

describe("TAS-54 branches", () => {
  test("company admin / branches marketing cannot move a geofence", async () => {
    await assertDeniedByRule(updateDoc(doc(as("admin-a"), "branches/br-a"), {geofenceRadius: 5000}));
    await assertDeniedByRule(updateDoc(doc(as("bm-a"), "branches/br-a"), {geofenceRadius: 5000}));
    await assertDeniedByRule(updateDoc(doc(as("admin-a"), `organizations/${ORG}/branches/br-a`), {geofenceRadius: 5000}));
  });
  test("org admin edits its own chain's branch, not another chain's", async () => {
    await assertSucceeds(updateDoc(doc(as("orgadmin"), "branches/br-a"), {geofenceRadius: 150}));
    await assertDeniedByRule(updateDoc(doc(as("orgadmin"), "branches/br-b"), {geofenceRadius: 150}));
    await assertDeniedByRule(updateDoc(doc(as("orgadmin"), "branches/br-a"), {organizationUID: ORG_B}));
  });
  test("super admin keeps the branches screens (add + nested mirror)", async () => {
    await assertSucceeds(setDoc(doc(as("sa"), "branches/br-new"), {branchName: "New", organizationUID: ORG_B, geofenceRadius: 100}));
    await assertSucceeds(setDoc(doc(as("sa"), `organizations/${ORG_B}/branches/br-new`), {branchName: "New"}, {merge: true}));
  });
});

describe("TAS-56 photo creates", () => {
  test("a photo permission cannot be created outside its company path", async () => {
    await assertDeniedByRule(setDoc(doc(delegate(), `organizations/${ORG_B}/companies/${CO_B}/photo_permissions/p1`), {
      organizationUID: ORG, companyUID: CO, delegateUID: "d1",
    }));
    await assertDeniedByRule(setDoc(doc(delegate(), "rogue/x/photo_permissions/p1"), {
      organizationUID: ORG, companyUID: CO, delegateUID: "d1",
    }));
  });
  test("the delegate still creates one in its own company", async () => {
    await assertSucceeds(setDoc(doc(delegate(), `organizations/${ORG}/companies/${CO}/photo_permissions/p-ok`), {
      organizationUID: ORG, companyUID: CO, delegateUID: "d1", status: "pending",
    }));
  });
});

describe("TAS-57 fraud logs and receipt codes", () => {
  test("company staff cannot edit or delete a fraud log", async () => {
    await assertDeniedByRule(updateDoc(doc(as("admin-a"), "security_audit_logs/log-a"), {status: "dismissed"}));
    await assertDeniedByRule(deleteDoc(doc(as("hr-a"), "security_audit_logs/log-a")));
  });
  test("technical support still removes a log", async () => {
    await assertSucceeds(deleteDoc(doc(as("tech"), "security_audit_logs/log-a")));
  });
  test("a receipt code is reserved for the caller's company only", async () => {
    await assertSucceeds(setDoc(doc(as("admin-a"), "used_receipt_codes/RC-NEW"), {
      receiptCode: "RC-NEW", companyUID: CO, organizationUID: ORG, status: "reserved", createdAt: serverTimestamp(),
    }));
    await assertDeniedByRule(setDoc(doc(as("admin-a"), "used_receipt_codes/RC-X"), {
      receiptCode: "RC-X", companyUID: CO_B, organizationUID: ORG, status: "reserved",
    }));
  });
  test("another company's reserved code cannot be taken over or released", async () => {
    await assertDeniedByRule(setDoc(doc(as("admin-a"), "used_receipt_codes/RC-B"), {companyUID: CO, status: "reserved"}));
    await assertDeniedByRule(deleteDoc(doc(as("admin-a"), "used_receipt_codes/RC-B")));
  });
  test("the reviewer (super admin) approves and rejects", async () => {
    await assertSucceeds(setDoc(doc(as("sa"), "used_receipt_codes/RC-A"), {status: "approved", approvedBy: "sa"}, {merge: true}));
    await assertSucceeds(deleteDoc(doc(as("sa"), "used_receipt_codes/RC-B")));
  });
});

describe("TAS-53 collections, floor checks, sent notifications", () => {
  test("accountant and org admin read collections but cannot write them", async () => {
    await assertSucceeds(getDoc(doc(as("acc-a"), "monthly_collections/2026-11")));
    await assertDeniedByRule(updateDoc(doc(as("acc-a"), "monthly_collections/2026-11"), {grandTotalDue: 1}));
    await assertDeniedByRule(setDoc(doc(as("orgadmin"), "monthly_collections/2026-11/transactions/t1"), {collectedAmount: 1}));
  });
  test("super admin keeps the collections screen", async () => {
    await assertSucceeds(setDoc(doc(as("sa"), "monthly_collections/2026-11"), {grandTotalDue: 10}, {merge: true}));
  });
  test("a delegate cannot write floor checks (incl. a colleague's)", async () => {
    await assertDeniedByRule(setDoc(doc(delegate(), "floor_checks/2026-11-24_br_d2"), {delegateId: "d1", status: "ok"}, {merge: true}));
  });
  test("branches marketing still verifies a floor", async () => {
    await assertSucceeds(setDoc(doc(as("bm-a"), "floor_checks/2026-11-24_br_d3"), {
      delegateId: "d3", branchName: "br", date: "2026-11-24", status: "verified", verifiedBy: "bm-a", updatedAt: serverTimestamp(),
    }, {merge: true}));
  });
  test("non-global staff read only their own sends", async () => {
    await assertSucceeds(getDoc(doc(as("hr-a"), "sent_notifications/s-own")));
    await assertDeniedByRule(getDoc(doc(as("admin-a"), "sent_notifications/s-other")));
    await assertDeniedByRule(getDoc(doc(as("orgadmin"), "sent_notifications/s-other")));
    await assertSucceeds(getDoc(doc(as("sa"), "sent_notifications/s-other")));
  });
});

describe("TAS-58 mail", () => {
  test("company / HR / org admin cannot queue an email", async () => {
    for (const uid of ["admin-a", "hr-a", "orgadmin", "tech"]) {
      await assertDeniedByRule(setDoc(doc(as(uid), `mail/m-${uid}`), {to: ["x@fake.test"], message: {subject: "s", html: "<b>x</b>"}}));
    }
  });
});

describe("TAS-59 company requests, private label, company doc", () => {
  test("company A admin cannot touch company B's request in the same chain", async () => {
    await assertDeniedByRule(updateDoc(doc(as("admin-a"), `organizations/${ORG}/companyRequests/cr-b`), {status: "approved"}));
    await assertDeniedByRule(deleteDoc(doc(as("admin-a"), `organizations/${ORG}/companyRequests/cr-b`)));
  });
  test("company B admin still updates its own request", async () => {
    await assertSucceeds(updateDoc(doc(as("admin-b"), `organizations/${ORG}/companyRequests/cr-b`), {status: "pending", updatedAt: serverTimestamp()}));
  });
  test("a delegate cannot edit its own audit (e.g. approve it)", async () => {
    await assertDeniedByRule(updateDoc(doc(delegate(), `organizations/${ORG}/private_label_audits/au-1`), {reviewStatus: "approved"}));
  });
  test("a delegate writes its own day doc, not a colleague's", async () => {
    await assertSucceeds(setDoc(doc(delegate(), `organizations/${ORG}/private_label_days/d1_2026-11-24`), {
      id: "d1_2026-11-24", delegateUid: "d1", organizationUID: ORG, companyUID: CO, type: "worked", auditsCount: 1,
    }));
    await assertDeniedByRule(updateDoc(doc(delegate(), `organizations/${ORG}/private_label_days/d2_2026-11-24`), {auditsCount: increment(5)}));
  });
  test("HR / accountant cannot edit the company doc; the company admin can", async () => {
    await assertDeniedByRule(updateDoc(doc(as("hr-a"), `organizations/${ORG}/companies/${CO}`), {deferredPayment: 0, name: "x"}));
    await assertDeniedByRule(updateDoc(doc(as("acc-a"), `organizations/${ORG}/companies/${CO}`), {deferredPayment: 0}));
    await assertSucceeds(updateDoc(doc(as("admin-a"), `organizations/${ORG}/companies/${CO}`), {commercialRegisterNumber: "1", updatedAt: serverTimestamp()}));
  });
});

describe("TAS-60 org-admin role from invites", () => {
  test("an 'org-admin' user is an org admin (edits its chain's branch)", async () => {
    await assertSucceeds(updateDoc(doc(as("orgadmin-invite"), "branches/br-a"), {geofenceRadius: 120}));
  });
});
