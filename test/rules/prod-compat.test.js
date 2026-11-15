/**
 * TA-60 prod compatibility: web dashboard + main v1.14.2 client operations
 * that prod rules allow. Emulator only (demo-ta60-prod-compat).
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
  query,
  where,
  doc,
  setDoc,
  updateDoc,
  getDocs,
  writeBatch,
  Timestamp,
} = require("firebase/firestore");
const {ref, uploadBytes, getBytes} = require("firebase/storage");

const PROJECT_ID = "demo-ta60-prod-compat";
const bytes = Uint8Array.from(Buffer.from("fixture\n"));
const exp = (days) => new Date(Date.now() + days * 864e5);

describe("TA-60 prod compatibility", () => {
  let env;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
      storage: {
        rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8"),
      },
    });
  });

  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const users = {
        oa: {role: "organization-admin", organizationUID: "o1", companyUID: "c1"},
        ca: {role: "company-admin", organizationUID: "o1", companyUID: "c1"},
        sup: {role: "supervisor", organizationUID: "o1", companyUID: "c1"},
        hr1: {role: "hr", organizationUID: "o1", companyUID: "c1"},
        mk: {role: "marketing", organizationUID: "o1", companyUID: "c1"},
        bmm: {role: "branches_marketing_manager", organizationUID: "o1", companyUID: "c1"},
        ts: {role: "technical_support", organizationUID: "o1"},
        sa: {role: "super-admin", organizationUID: "o1"},
        dlg: {role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "dlg1"},
        invitee: {role: "company-admin", organizationUID: "o1", companyUID: "c1", email: "inv@example.com"},
        dlg1: {role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "dlg1"},
      };
      for (const [id, d] of Object.entries(users)) {
        await db.doc(`users/${id}`).set(d);
      }
      await db.doc("organizations/o1").set({name: "Org1", companyUID: "c1"});
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc("organizations/o1/companies/c1/delegates/d1").set({
        uid: "d1", organizationUID: "o1", companyUID: "c1",
        nationalId: "29101010100011", nationalityID: "29101010100011", status: "active",
      });
      await db.doc("delegate_requests/fin1").set({
        organizationUID: "o1", organizationId: "o1", companyUID: "c1", companyId: "c1",
        status: "pending", requestType: "renewal", supervisorUid: "sup", paymentStatus: "unpaid",
      });
      await db.doc("monthly_collections/2026-01").set({period: "2026-01", organizationUID: "o1"});
      await db.doc("notifications/co-broadcast").set({
        title: "Co", body: "b", delegateUid: "company_c1",
        organizationId: "o1", companyId: "c1", isRead: false,
      });
      await db.doc("notifications/sup-broadcast").set({
        title: "Sup", body: "b", delegateUid: "supervisor_c1",
        organizationId: "o1", companyId: "c1", isRead: false,
      });
      await db.doc("notifications/all-sup-broadcast").set({
        title: "All", body: "b", delegateUid: "all_company_supervisors",
        organizationId: "o1", companyId: "c1", isRead: false,
      });
      await db.doc("invites/inv1").set({
        status: "pending", organizationId: "o1", companyId: "c1",
        roleToAssign: "company-admin", email: "inv@example.com", expiresAt: exp(3),
      });
      await db.doc("attendance_logs/a1").set({
        delegateId: "d1", organizationId: "o1", companyId: "c1",
        type: "check_in", timestamp: new Date("2026-11-11T08:00:00.000Z"),
      });
      await db.doc("delegate_requests/n1").set({
        requestType: "new_delegate", status: "pending", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
        nationalId: "29101010100101", phoneNumber: "01000000001",
        fullName: "New", profileImageUrl: "p0",
      });
      await db.doc("organizations/o1/companies/c1/delegates/n1").set({
        uid: "n1", status: "pending", organizationUID: "o1", companyUID: "c1",
        documents: [{documentKey: "personalPhoto", documentStatus: "pending", documentURL: "p0"}],
      });
    });
  });

  const as = (uid, claims = {}) =>
    env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}, ...claims});
  const fs = (uid, claims) => as(uid, claims).firestore();
  const st = (uid, claims) => as(uid, claims).storage();
  const del = () => as("dlg1", {
    role: "delegate", delegateId: "dlg1", orgId: "o1", companyId: "c1",
    firebase: {sign_in_provider: "custom"},
  });

  test("org-admin lists financial delegate_requests and monthly_collections", async () => {
    const db = fs("oa");
    await assertSucceeds(getDocs(collection(db, "delegate_requests")));
    await assertSucceeds(getDocs(collection(db, "monthly_collections")));
    await assertSucceeds(db.doc("monthly_collections/2026-01").get());
  });

  test("org-admin nationalId duplicate check on nested delegates", async () => {
    const db = fs("oa");
    await assertSucceeds(getDocs(query(
      collection(db, "organizations/o1/companies/c1/delegates"),
      where("nationalId", "==", "29101010100011"),
    )));
    await assertSucceeds(getDocs(query(
      collectionGroup(db, "delegates"),
      where("organizationUID", "==", "o1"),
      where("nationalId", "==", "29101010100011"),
    )));
  });

  test("company-admin reads and marks company notification read", async () => {
    const db = fs("ca");
    await assertSucceeds(db.doc("notifications/co-broadcast").get());
    await assertSucceeds(updateDoc(doc(db, "notifications/co-broadcast"), {isRead: true}));
  });

  test("supervisor reads company and supervisor broadcasts", async () => {
    const db = fs("sup");
    await assertSucceeds(db.doc("notifications/sup-broadcast").get());
    await assertSucceeds(db.doc("notifications/co-broadcast").get());
    await assertSucceeds(db.doc("notifications/all-sup-broadcast").get());
    await assertSucceeds(getDocs(query(
      collection(db, "notifications"),
      where("delegateUid", "==", "supervisor_c1"),
    )));
  });

  test("website client-side invite claim by invitee", async () => {
    const db = fs("invitee", {email: "inv@example.com", email_verified: true});
    await assertSucceeds(updateDoc(doc(db, "invites/inv1"), {
      status: "claimed",
      claimedByUid: "invitee",
      claimedAt: new Date().toISOString(),
    }));
  });

  const penaltyModelPayload = (status, id) => ({
    penaltyId: id,
    companyId: "c1",
    companyName: "Company One",
    createdById: "sup",
    createdByName: "Supervisor",
    title: "Late",
    category: "DATA_MISSING",
    incidentDescription: "desc",
    fineAmount: 500,
    currency: "EGP",
    status,
    evidenceFiles: [],
    targetDelegateId: "d1",
    targetDelegateName: "Delegate",
    isRepeated: false,
    isConfidential: false,
    createdAt: Timestamp.fromDate(new Date("2026-11-11T10:00:00.000Z")),
    updatedAt: Timestamp.fromDate(new Date("2026-11-11T10:00:00.000Z")),
  });

  for (const [who, status] of [
    ["sup", "PENDING_BRANCHES_MARKETING"],
    ["ca", "ISSUED"],
    ["hr1", "PENDING_BRANCHES_MARKETING"],
  ]) {
    test(`${who} creates penalty PenaltyModel status ${status}`, async () => {
      const id = `p-${who}-${status}`;
      await assertSucceeds(setDoc(doc(fs(who), `penalties/${id}`), penaltyModelPayload(status, id)));
    });
  }

  test("supervisor creates notifications to all broadcast targets", async () => {
    const db = fs("sup");
    const base = {
      title: "t", body: "b", type: "penalty", companyId: "c1", companyName: "C1",
      createdById: "sup", createdByName: "Sup", senderName: "Sup", senderRole: "supervisor",
      isRead: false, read: false, createdAt: Timestamp.now(), deletedBy: [],
    };
    for (const [i, delegateUid] of [
      "d1", "company_c1", "supervisor_c1", "all_company_supervisors", "branchesMarketingManager",
    ].entries()) {
      await assertSucceeds(setDoc(doc(db, `notifications/sup-n-${i}`), {...base, delegateUid}));
    }
    await assertSucceeds(setDoc(doc(db, "notifications/sup-sa"), {
      ...base, delegateUid: "superAdmin", type: "penalty",
    }));
  });

  test("delegate attendance_check_in to supervisor and company broadcasts", async () => {
    const ddb = del().firestore();
    const base = {
      title: "حضور", body: "b", type: "attendance_check_in", attendanceType: "check_in",
      companyId: "c1", organizationId: "o1", targetDelegateId: "dlg1",
      targetDelegateName: "Del", senderName: "Del", senderRole: "delegate",
      isRead: false, read: false, createdAt: Timestamp.now(), deletedBy: [],
    };
    await assertSucceeds(setDoc(doc(ddb, "notifications/att-sup"), {...base, delegateUid: "sup"}));
    for (const [i, delegateUid] of ["supervisor_c1", "company_c1", "all_company_supervisors"].entries()) {
      await assertSucceeds(setDoc(doc(ddb, `notifications/att-b-${i}`), {...base, delegateUid}));
    }
  });

  test("super-admin approves new_delegate request alone (prod v1.14.2)", async () => {
    const db = fs("sa");
    await assertSucceeds(updateDoc(doc(db, "delegate_requests/n1"), {
      status: "approved", reviewedBy: "sa", reviewedAt: "t",
    }));
  });

  test("tech approves new_delegate batched (matches docs-pending r5)", async () => {
    const PHOTO = {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "p0"};
    const NID = {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f0", secondaryURL: "b0"};
    const RCPT = {documentKey: "paymentReceipt", documentStatus: "approved", documentURL: "r0"};
    const BASE = {
      uid: "n2", organizationUID: "o1", companyUID: "c1", status: "active", fullName: "Fake",
      profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0",
      phoneNumber: "01000000002",
    };
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("delegate_requests/n2").set({
        status: "pending", requestType: "new_delegate", orgCompanyCheck: "ok",
        organizationUID: "o1", companyUID: "c1", supervisorUid: "sup",
        fullName: "Fake", nationalId: "", phoneNumber: "01000000002",
        profileImageUrl: "p0", nationalIdFrontUrl: "f0", nationalIdBackUrl: "b0", receiptImageUrl: "r0",
      });
      await db.doc("organizations/o1/companies/c1/delegates/n2").set({
        ...BASE, status: "pending",
        documents: [
          {...PHOTO, documentStatus: "pending"},
          {...NID, documentStatus: "pending"},
          {...RCPT, documentStatus: "pending"},
        ],
      });
    });
    const db = fs("ts");
    const batch = writeBatch(db);
    batch.update(doc(db, "delegate_requests/n2"), {status: "approved", reviewedBy: "ts", reviewedAt: "t"});
    batch.set(doc(db, "organizations/o1/companies/c1/delegates/n2"), {
      ...BASE, documents: [PHOTO, NID, RCPT],
    });
    await assertSucceeds(batch.commit());
  });

  test("supervisor marketing bmm attendance list queries", async () => {
    const start = new Date("2026-11-11T00:00:00.000Z");
    const end = new Date("2026-11-12T00:00:00.000Z");
    for (const uid of ["sup", "mk", "bmm"]) {
      const db = fs(uid);
      await assertSucceeds(getDocs(query(
        collection(db, "attendance_logs"),
        where("organizationId", "==", "o1"),
        where("companyId", "==", "c1"),
        where("timestamp", ">=", start),
        where("timestamp", "<=", end),
      )));
    }
  });

  describe("storage backward compatibility", () => {
    test("same-company staff staging/requests without intent", async () => {
      const hr = st("ca");
      await assertSucceeds(uploadBytes(ref(hr, "staging/requests/fin1/doc.jpg"), bytes));
      await assertSucceeds(getBytes(ref(hr, "staging/requests/fin1/doc.jpg")));
    });

    test("supervisor delegate_documents without intent (legacy registration)", async () => {
      const sup = st("sup");
      await assertSucceeds(uploadBytes(ref(sup, "delegate_documents/dlg1/id.jpg"), bytes));
    });

    test("delegate_subscription_receipts without intent", async () => {
      const sup = st("sup");
      await assertSucceeds(uploadBytes(ref(sup, "delegate_subscription_receipts/n1/rcpt.jpg"), bytes));
    });

    test("org-admin company SDK files path", async () => {
      const oa = st("oa");
      await assertSucceeds(uploadBytes(ref(oa, "organizations/o1/companies/c1/files/logo.png"), bytes));
    });

    test("supervisor legacy penalties/evidence upload", async () => {
      const sup = st("sup");
      await assertSucceeds(uploadBytes(ref(sup, "penalties/evidence/p1.jpg"), bytes));
    });
  });
});