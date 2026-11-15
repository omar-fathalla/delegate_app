/**
 * TA-8 rules gaps (Mohamed 14 Nov): emulator-only probes.
 * npm: npx firebase-tools emulators:exec --only firestore --project demo-ta8-gaps "node --test test/rules/company-scoping-gaps.test.js"
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, updateDoc, setDoc, deleteDoc} = require("firebase/firestore");

/** Mirrors `pendingDelegateDataFor` in delegate_subscription_repository_impl.dart */
function pendingDelegatePlaceholderPayload(requestId) {
  const uploadedAt = new Date().toISOString();
  return {
    uid: requestId,
    firstName: "Ali",
    secondName: "Hassan",
    thirdName: "Omar",
    fullName: "Ali Hassan Omar",
    phoneNumber: "01077777777",
    nationalId: "29001011234567",
    nationalityID: "29001011234567",
    organizationUID: "o1",
    organizationName: "O1",
    companyUID: "c1",
    companyName: "C1",
    profileImageUrl: "https://cdn.example/p.jpg",
    nationalIdFrontUrl: "https://cdn.example/f.jpg",
    nationalIdBackUrl: "https://cdn.example/b.jpg",
    documents: [
      {
        documentKey: "personalPhoto",
        documentStatus: "pending",
        documentURL: "https://cdn.example/p.jpg",
        uploadedAt,
      },
      {
        documentKey: "nationalityId",
        documentStatus: "pending",
        documentURL: "https://cdn.example/f.jpg",
        secondaryURL: "https://cdn.example/b.jpg",
        uploadedAt,
      },
      {
        documentKey: "paymentReceipt",
        documentStatus: "pending",
        documentURL: "https://cdn.example/r.jpg",
        receiptCode: "12345",
        uploadedAt,
      },
    ],
    status: "pending",
    position: "Promoter",
    role: "delegate",
    registeredVia: "mobile_app",
    originOrganizationUID: "o1",
    originOrganizationName: "O1",
    isDeductedFromCompany: false,
    receiptCode: "12345",
    subscriptionCycle: "H1",
    subscription: {
      periodCode: "H1",
      periodStart: 1,
      periodEnd: 30,
      amountDue: 100,
      paymentStatus: "unpaid",
      registrationRequestId: requestId,
    },
  };
}

function pendingForOrg(requestId, orgId, orgName) {
  return {
    ...pendingDelegatePlaceholderPayload(requestId),
    organizationUID: orgId,
    organizationName: orgName,
    originOrganizationUID: orgId,
    originOrganizationName: orgName,
  };
}

function eightPendingDocs() {
  const uploadedAt = new Date().toISOString();
  return Array.from({length: 8}, (_, i) => ({
    documentKey: `doc${i}`,
    documentStatus: "pending",
    documentURL: `https://cdn.example/d${i}.jpg`,
    uploadedAt,
  }));
}

describe("TA-8 security rules gaps", () => {
  let env;
  const as = (uid) => env.authenticatedContext(uid, {firebase: {sign_in_provider: "password"}}).firestore();

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-ta8-gaps",
      firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
    });
  });
  after(async () => env.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/sup").set({
        role: "supervisor", organizationUID: "o1", companyUID: "c1", isActive: false,
      });
      await db.doc("users/ca").set({
        role: "company-admin", organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("users/csup").set({
        role: "company_supervisor", organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("users/hr").set({role: "hr", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/oa").set({
        role: "organization-admin", organizationUID: "o1", companyUID: "c1",
      });
      await db.doc("users/mk").set({role: "marketing", organizationUID: "o1", companyUID: "c1"});
      await db.doc("users/d1").set({
        role: "delegate", organizationUID: "o1", companyUID: "c1", uid: "d1", status: "active",
      });
      await db.doc("organizations/o1").set({name: "O1"});
      await db.doc("organizations/o1/companies/c1").set({name: "C1"});
      await db.doc("organizations/o1/companies/c1/delegates/d1").set({
        organizationUID: "o1", companyUID: "c1", status: "active", phoneNumber: "01011111111",
        profileImageUrl: "https://cdn.example/p0.jpg",
        personalPhotoURL: "https://cdn.example/p0.jpg",
        photoURL: "https://cdn.example/p0.jpg",
        documents: [{
          documentKey: "personalPhoto", documentStatus: "approved",
          documentURL: "https://cdn.example/p0.jpg", uploadedAt: "2026-01-01",
        }],
      });
      await db.doc("delegate_requests/r1").set({
        requestType: "renewal", status: "pending", organizationUID: "o1", companyUID: "c1",
        supervisorUid: "sup",
      });
    });
  });

  test("DENY company staff reassigns supervisorUid on a delegate_request (gap a)", () =>
    assertFails(updateDoc(doc(as("sup"), "delegate_requests/r1"), {
      supervisorUid: "hr", updatedAt: "t",
    })));

  test("DENY company staff mutates requestType on a delegate_request (gap a)", () =>
    assertFails(updateDoc(doc(as("hr"), "delegate_requests/r1"), {
      requestType: "new_delegate", updatedAt: "t",
    })));

  test("ALLOW company staff may still touch updatedAt only", () =>
    assertSucceeds(updateDoc(doc(as("sup"), "delegate_requests/r1"), {updatedAt: "t"})));

  test("ALLOW company staff may cancel unpaid renewal", () =>
    assertSucceeds(updateDoc(doc(as("sup"), "delegate_requests/r1"), {status: "cancelled"})));

  test("DENY marketing cannot update delegate_requests (gap a)", () =>
    assertFails(updateDoc(doc(as("mk"), "delegate_requests/r1"), {updatedAt: "t"})));

  test("DENY supervisor self-activates isActive on own users doc (gap b)", () =>
    assertFails(updateDoc(doc(as("sup"), "users/sup"), {isActive: true})));

  test("DENY supervisor self-activates via isActive on own users doc as company staff", () =>
    assertFails(updateDoc(doc(as("sup"), "users/sup"), {displayName: "S", isActive: true})));

  test("DENY company staff may not set isActive true on another staff user", () =>
    assertFails(updateDoc(doc(as("oa"), "users/sup"), {isActive: true})));

  test("ALLOW org-admin may still deactivate staff", () =>
    assertSucceeds(updateDoc(doc(as("oa"), "users/sup"), {isActive: false})));

  test("DENY H-1: supervisor cannot suspend delegate via status spelling bypass", () =>
    assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "SUSPENDED", updatedAt: "t",
    })));

  test("DENY H-1: HR cannot deactivate delegate via isActive on nested delegate", () =>
    assertFails(updateDoc(doc(as("hr"), "organizations/o1/companies/c1/delegates/d1"), {
      isActive: false, updatedAt: "t",
    })));

  for (const st of ["disabled", "blocked", "rejected", "active ", " ACTIVE"]) {
    test(`DENY H-1: supervisor status variant '${st}' on delegate`, () =>
      assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
        status: st, updatedAt: "t",
      })));
  }

  test("DENY H-1: supervisor bare status-only active to pending", () =>
    assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "pending", updatedAt: "t",
    })));

  test("DENY company_admin bare active to pending", () =>
    assertFails(updateDoc(doc(as("ca"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "pending", updatedAt: "t",
    })));

  test("ALLOW H-1: supervisor re-upload shape may set active delegate to pending", () =>
    assertSucceeds(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "pending",
      updatedAt: "t",
      documents: [{
        documentKey: "personalPhoto", documentStatus: "pending",
        documentURL: "https://cdn.example/p1.jpg", uploadedAt: "2026-11-15",
      }],
    })));

  test("DENY supervisor cannot set active delegate pending with extra fields", () =>
    assertFails(updateDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "pending", updatedAt: "t", fullName: "x",
      documents: [{
        documentKey: "personalPhoto", documentStatus: "pending",
        documentURL: "https://cdn.example/p1.jpg", uploadedAt: "2026-11-15",
      }],
    })));

  test("DENY H-1: supervisor cannot create nested delegate with active status", () =>
    assertFails(setDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d-new"), {
      organizationUID: "o1", companyUID: "c1", status: "active", phoneNumber: "01099999999",
    })));

  test("ALLOW H-1: supervisor may create nested delegate pending only", () =>
    assertSucceeds(setDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/d-new2"), {
      organizationUID: "o1", companyUID: "c1", status: "pending", phoneNumber: "01088888888",
    })));

  test("DENY H-1: HR cannot flip active delegate status back to pending", () =>
    assertFails(updateDoc(doc(as("hr"), "organizations/o1/companies/c1/delegates/d1"), {
      status: "pending", updatedAt: "t",
    })));

  test("DENY company admin cannot reassign delegate user to hr via users doc", async () => {
    await assertFails(updateDoc(doc(as("ca"), "users/d1"), {role: "hr", updatedAt: "t"}));
  });

  test("DENY company staff cannot create users doc for active delegate", () =>
    assertFails(setDoc(doc(as("ca"), "users/new-del"), {
      role: "delegate", organizationUID: "o1", companyUID: "c1", status: "active", uid: "new-del",
    })));

  test("DENY org admin cannot create users doc for active delegate", () =>
    assertFails(setDoc(doc(as("oa"), "users/new-del-oa"), {
      role: "delegate", organizationUID: "o1", companyUID: "c1", status: "active", uid: "new-del-oa",
    })));

  test("ALLOW org admin may create pending delegate users doc", () =>
    assertSucceeds(setDoc(doc(as("oa"), "users/new-del-oa2"), {
      role: "delegate", organizationUID: "o1", companyUID: "c1", status: "pending", uid: "new-del-oa2",
    })));

  for (const [label, uid] of [
    ["supervisor", "sup"],
    ["company_supervisor", "csup"],
    ["company_admin", "ca"],
  ]) {
    test(`ALLOW H-1: ${label} create pending delegate placeholder (Dart shape)`, () => {
      const reqId = `req-${uid}`;
      return assertSucceeds(setDoc(
        doc(as(uid), "organizations/o1/companies/c1/delegates/" + reqId),
        pendingDelegatePlaceholderPayload(reqId),
      ));
    });
  }

  test("DENY supervisor cannot create pending delegate with approved document entry", () =>
    assertFails(setDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/bad-docs"), {
      ...pendingDelegatePlaceholderPayload("bad-docs"),
      documents: [
        {
          documentKey: "personalPhoto",
          documentStatus: "approved",
          documentURL: "https://cdn.example/p.jpg",
        },
        {
          documentKey: "nationalityId",
          documentStatus: "pending",
          documentURL: "https://cdn.example/f.jpg",
        },
      ],
    })));

  test("DENY HR cannot create pending delegate placeholder", () =>
    assertFails(setDoc(
      doc(as("hr"), "organizations/o1/companies/c1/delegates/hr-ph"),
      pendingDelegatePlaceholderPayload("hr-ph"),
    )));

  test("DENY placeholder create when documents is a map not a list", () =>
    assertFails(setDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/map-docs"), {
      ...pendingDelegatePlaceholderPayload("map-docs"),
      documents: {personalPhoto: {documentStatus: "pending", documentURL: "https://cdn.example/p.jpg"}},
    })));

  test("DENY placeholder with approved document at slot index 5", () => {
    const docs = eightPendingDocs();
    docs[5] = {...docs[5], documentStatus: "approved"};
    return assertFails(setDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/slot5"), {
      ...pendingDelegatePlaceholderPayload("slot5"),
      documents: docs,
    }));
  });

  test("DENY supervisor placeholder in another company under same org", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("organizations/o1/companies/c2").set({name: "C2"});
    });
    await assertFails(setDoc(
      doc(as("sup"), "organizations/o1/companies/c2/delegates/cross-co"),
      {...pendingForOrg("cross-co", "o1", "O1"), companyUID: "c2", companyName: "C2"},
    ));
  });

  test("DENY supervisor placeholder when payload companyUID mismatches path", () =>
    assertFails(setDoc(doc(as("sup"), "organizations/o1/companies/c1/delegates/bad-co"), {
      ...pendingDelegatePlaceholderPayload("bad-co"),
      companyUID: "c2",
      companyName: "C2",
    })));

  test("DENY supervisor placeholder when payload organizationUID mismatches path", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("organizations/o2").set({name: "O2"});
      await ctx.firestore().doc("organizations/o2/companies/c1").set({name: "C1"});
    });
    await assertFails(setDoc(doc(as("sup"), "organizations/o2/companies/c1/delegates/bad-org"), {
      ...pendingDelegatePlaceholderPayload("bad-org"),
      organizationUID: "o1",
      organizationName: "O1",
    }));
  });

  for (const [label, uid] of [
    ["supervisor", "sup"],
    ["company_supervisor", "csup"],
    ["company_admin", "ca"],
  ]) {
    test(`ALLOW ${label} placeholder when path and payload company/org match`, () => {
      const reqId = `match-${uid}`;
      return assertSucceeds(setDoc(
        doc(as(uid), "organizations/o1/companies/c1/delegates/" + reqId),
        pendingDelegatePlaceholderPayload(reqId),
      ));
    });
  }

  for (const [label, uid] of [
    ["supervisor", "sup"],
    ["company_supervisor", "csup"],
    ["company_admin", "ca"],
  ]) {
    test(`ALLOW ${label} second-chain same-company placeholder (o2)`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("organizations/o2").set({name: "O2"});
        await ctx.firestore().doc("organizations/o2/companies/c1").set({name: "C1"});
      });
      const reqId = `req-o2-${uid}`;
      await assertSucceeds(setDoc(
        doc(as(uid), "organizations/o2/companies/c1/delegates/" + reqId),
        pendingForOrg(reqId, "o2", "O2"),
      ));
    });
  }

  test("DENY org admin cannot delete delegate_requests in another org", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("delegate_requests/foreign").set({
        organizationUID: "o2", companyUID: "c9", status: "pending", requestType: "renewal",
      });
    });
    await assertFails(deleteDoc(doc(as("oa"), "delegate_requests/foreign")));
  });

  test("ALLOW org admin may delete own-org delegate_requests", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("delegate_requests/own").set({
        organizationUID: "o1", companyUID: "c1", status: "pending", requestType: "renewal",
      });
    });
    await assertSucceeds(deleteDoc(doc(as("oa"), "delegate_requests/own")));
  });
});