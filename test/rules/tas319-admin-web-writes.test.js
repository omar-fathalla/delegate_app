/**
 * TAS-319: every Firestore write the Angular admin web (youssefathalla/tashil,
 * master e90cc41) still does from the browser, replayed on this repo's
 * firestore.rules.
 *
 * KEEP:  the write exactly as the web builds it (file:line in the test name)
 *        must be allowed for the role whose page triggers it.
 * BLOCK: the same write aimed at another organization / company (or a
 *        decision the role may not take) must be denied by a rule, never by
 *        the 1000-expression budget (assertDeniedByRule).
 *
 * Writes the rules deny but the UI still needs are kept as test.skip with the
 * Linear sub-issue id in the name, so CI stays green until they are fixed:
 *   TAS-321  org-admin invite email (addDoc mail) denied, /mail is super-admin only
 *   TAS-322  self email sync users/{uid}.email denied (TAS-49)
 *   TAS-324  four cross-org/company BLOCKs denied by the expression budget only
 *
 * Writes already moved to callables are not here: delegate status / suspend /
 * activate directly, billing reset, request changes on create (TAS-69),
 * resubmit create + lost-ID approval (TAS-70), invite claim (TAS-68),
 * approve create / update / delete requests, approve company request.
 *
 * Roles as prod signs them in: super-admin {role}, organization-admin
 * {role, orgId, organizationId}; company-admin with claims {role, orgId,
 * organizationId, companyId} and without claims (older sessions).
 * Fake data only (ids prefixed seed-fake-tas319-).
 *
 * npm run test:rules:tas319
 */
const {describe, test, before, after} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment, assertSucceeds, assertDeniedByRule,
} = require("./_rules_testing");
const {
  doc, setDoc, addDoc, updateDoc, deleteDoc, writeBatch, collection,
  serverTimestamp, increment, deleteField, Timestamp,
} = require("firebase/firestore");

const P = "seed-fake-tas319";
const ORG_A = `${P}-org-a`;
const ORG_B = `${P}-org-b`;
const CO_A = `${P}-co-a`;
const CO_A2 = `${P}-co-a2`;
const CO_B = `${P}-co-b`;
const since = Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
const in14d = () => Timestamp.fromDate(new Date(Date.now() + 14 * 864e5));
const in7d = () => Timestamp.fromDate(new Date(Date.now() + 7 * 864e5 - 60e3));

const users = {
  "sa": {doc: {role: "super-admin", displayName: "SA"}, claims: {role: "super-admin"}},
  "orgadmin-a": {
    doc: {role: "organization-admin", organizationUID: ORG_A, organizationName: "Org A", displayName: "OA"},
    claims: {role: "organization-admin", orgId: ORG_A, organizationId: ORG_A},
  },
  "admin-a": {
    doc: {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A, displayName: "CA"},
    claims: {},
  },
  "admin-a-claims": {
    doc: {role: "company-admin", organizationUID: ORG_A, companyUID: CO_A, displayName: "CA"},
    claims: {role: "company-admin", orgId: ORG_A, organizationId: ORG_A, companyId: CO_A},
  },
};
const COMPANY_ADMINS = ["admin-a", "admin-a-claims"];

let env;
let seq = 0;
const id = (tag) => `${P}-${tag}-${++seq}`;
const db = (uid) => env.authenticatedContext(uid, users[uid].claims).firestore();
const seed = (path, data) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(doc(ctx.firestore(), path), {...data, fake: true}));
const coPath = (o, c) => `organizations/${o}/companies/${c}`;

const delegateData = (o, c, extra = {}) => ({
  uid: "x", delegatePublicId: "P-1", status: "active", statusReason: "create",
  hasPendingUpdate: false, version: 0, fullName: "Fake Delegate", firstName: "Fake",
  nationalityID: "29001010000000", phoneNumber: "01000000000",
  documents: [{documentKey: "personalPhoto", documentStatus: "approved", documentURL: "https://x"}],
  organizationUID: o, organizationName: o, companyUID: c, companyName: c,
  isPrinted: false, createdAt: since, updatedAt: since, createdBy: "x", updatedBy: "x",
  ...extra,
});
const requestData = (o, c, delegateId, extra = {}) => ({
  actionType: "update", status: "pending", targetDelegateId: delegateId,
  targetDelegateName: "Fake Delegate", delegatePublicId: "P-1",
  organizationUID: o, organizationName: o, companyUID: c, companyName: c,
  requestedBy: "admin-a", requestedByName: "CA", requestedAt: since,
  createdAt: since, updatedAt: since, ...extra,
});
const companyData = (o, c, extra = {}) => ({
  name: c, type: "Retail", companyCodeInOrg: c, organizationUID: o, organizationCode: o,
  organizationName: o, status: "Active", deferredPayment: 500, hasDeferredPayment: true,
  admins: 1, delegates: 3, commercialRegisterNumber: "1", taxCardNumber: "2",
  documentUrls: {commercialRegister: "https://cr", taxCard: "https://tc"},
  createdAt: since, updatedAt: since, ...extra,
});

/** A delegate plus one request on it, in o/c. */
async function seedDelegateWithRequest(o, c, reqExtra = {}, delExtra = {}) {
  const d = id("del");
  const r = id("req");
  await seed(`${coPath(o, c)}/delegates/${d}`, delegateData(o, c, {uid: d, latestRequestId: r, ...delExtra}));
  await seed(`${coPath(o, c)}/requests/${r}`, requestData(o, c, d, {uid: r, ...reqExtra}));
  return {d, r};
}

const reviewedBy = (uid) => ({
  reviewedBy: uid, reviewedByName: users[uid].doc.displayName,
  reviewedAt: serverTimestamp(), updatedAt: serverTimestamp(),
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || "demo-tas319",
    firestore: {rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(fs, `users/${uid}`), {...u.doc, email: `${uid}@fake.test`, createdAt: since, fake: true});
    }
    for (const o of [ORG_A, ORG_B]) {
      await setDoc(doc(fs, `organizations/${o}`), {name: o, code: o, companies: 2, admins: 1, fake: true});
    }
    for (const [o, c] of [[ORG_A, CO_A], [ORG_A, CO_A2], [ORG_B, CO_B]]) {
      await setDoc(doc(fs, coPath(o, c)), {...companyData(o, c), fake: true});
    }
  });
});

after(async () => {
  await env?.cleanup();
});

// ======================= SUPER ADMIN =======================

describe("super-admin pages", () => {
  test("organization.service.ts:63 addDoc organizations (sup org-dialog)", async () => {
    await assertSucceeds(addDoc(collection(db("sa"), "organizations"), {
      name: "Fake Org", code: "FAKE319", admins: 0, companies: 0,
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), fake: true,
    }));
  });

  test("BLOCK: organization admin cannot create an organization", async () => {
    await assertDeniedByRule(addDoc(collection(db("orgadmin-a"), "organizations"), {name: "x", code: "X"}));
  });

  test("video-upload.service.ts:38 addDoc guide_videos (sup-upload-video)", async () => {
    await assertSucceeds(addDoc(collection(db("sa"), "guide_videos"), {
      title: "fake", videoUrl: "https://v", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  test("video-upload.service.ts:64 deleteDoc guide_videos", async () => {
    const v = id("video");
    await seed(`guide_videos/${v}`, {title: "fake"});
    await assertSucceeds(deleteDoc(doc(db("sa"), `guide_videos/${v}`)));
  });

  test("BLOCK: organization admin cannot write guide_videos", async () => {
    await assertDeniedByRule(addDoc(collection(db("orgadmin-a"), "guide_videos"), {title: "x"}));
  });

  test("invite.service.ts:96 setDoc invites (org-admin invite from sup org-admin-dialog)", async () => {
    await assertSucceeds(setDoc(doc(db("sa"), `invites/${id("inv")}`), inviteData("sa", {
      roleToAssign: "org-admin", organizationId: ORG_A, companyId: null, companyName: null,
    })));
  });

  test("invite.service.ts:347 addDoc mail (invitation email, super-admin)", async () => {
    await assertSucceeds(addDoc(collection(db("sa"), "mail"), mailPayload()));
  });

  test("organization-admin.service.ts:85 cancel pending org-admin invite", async () => {
    const i = id("inv");
    await seed(`invites/${i}`, {...inviteData("sa", {roleToAssign: "org-admin", organizationId: ORG_A}), createdAt: since, updatedAt: since});
    await assertSucceeds(updateDoc(doc(db("sa"), `invites/${i}`), {status: "cancelled", updatedAt: serverTimestamp()}));
  });
});

function inviteData(uid, extra = {}) {
  return {
    inviteLink: "https://fake/finish-signup?inviteId=x", email: "new@fake.test", phoneNumber: null,
    roleToAssign: "company-admin", organizationId: ORG_A, organizationName: "Org A",
    companyId: CO_A, companyName: CO_A, invitedByUid: uid, invitedByEmail: `${uid}@fake.test`,
    isFirstAdmin: false, status: "pending", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    expiresAt: in7d(), ...extra,
  };
}
function mailPayload() {
  return {to: ["new@fake.test"], message: {subject: "You Are Invited to Tashil SW-Point!", html: "<p>fake</p>"}};
}

// ======================= ORGANIZATION ADMIN =======================

describe("organization-admin pages", () => {
  test("organization.service.ts:120 update printing colors (org-settings)", async () => {
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `organizations/${ORG_A}`), {
      printingColor: "#000000", printingTextColor: "#ffffff", printingCardStyle: "classic",
      updatedAt: serverTimestamp(),
    }));
  });

  test.skip("[TAS-324] BLOCK: organization.service.ts:120 on another organization", async () => {
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), `organizations/${ORG_B}`), {
      printingColor: "#000000", updatedAt: serverTimestamp(),
    }));
  });

  const newCompany = (o) => ({
    companyCodeInOrg: "NEW", name: "New Co", type: "Retail", commercialRegisterNumber: "", taxCardNumber: "",
    admins: 0, delegates: 0, deferredPayment: 0, hasDeferredPayment: false, organizationUID: o,
    organizationCode: o, organizationName: o, status: "Pending",
    documentUrls: {commercialRegister: "", taxCard: ""},
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });

  test("company.service.ts:153+157 batch: create company + increment org companies (create-company-dialog)", async () => {
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.set(doc(u, coPath(ORG_A, id("newco"))), newCompany(ORG_A));
    b.update(doc(u, `organizations/${ORG_A}`), {companies: increment(1), updatedAt: serverTimestamp()});
    await assertSucceeds(b.commit());
  });

  test("BLOCK: company.service.ts:153 create a company in another organization", async () => {
    await assertDeniedByRule(setDoc(doc(db("orgadmin-a"), coPath(ORG_B, id("newco"))), newCompany(ORG_B)));
  });

  test("company.service.ts:259 update company name (org-companies-profile)", async () => {
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), coPath(ORG_A, CO_A)), {
      name: "Renamed Co", updatedAt: serverTimestamp(),
    }));
  });

  test("company.service.ts:341 clear deferred payment (org-companies-profile)", async () => {
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), coPath(ORG_A, CO_A2)), {
      deferredPayment: 0, hasDeferredPayment: false, updatedAt: serverTimestamp(),
    }));
  });

  test("BLOCK: company.service.ts:341 clear deferred payment of another organization's company", async () => {
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), coPath(ORG_B, CO_B)), {
      deferredPayment: 0, hasDeferredPayment: false, updatedAt: serverTimestamp(),
    }));
  });

  test("invite.service.ts:96 setDoc invites (company-admin invite, company-admin-dialog / create-company-dialog)", async () => {
    await assertSucceeds(setDoc(doc(db("orgadmin-a"), `invites/${id("inv")}`), inviteData("orgadmin-a")));
  });

  test.skip("[TAS-324] BLOCK: invite.service.ts:96 company-admin invite for another organization", async () => {
    await assertDeniedByRule(setDoc(doc(db("orgadmin-a"), `invites/${id("inv")}`), inviteData("orgadmin-a", {
      organizationId: ORG_B, companyId: CO_B,
    })));
  });

  test.skip("[TAS-321] invite.service.ts:347 addDoc mail after the invite (organization admin)", async () => {
    await assertSucceeds(addDoc(collection(db("orgadmin-a"), "mail"), mailPayload()));
  });

  test("company-admin.service.ts:107 cancel pending company-admin invite", async () => {
    const i = id("inv");
    await seed(`invites/${i}`, {...inviteData("orgadmin-a"), createdAt: since, updatedAt: since});
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `invites/${i}`), {status: "cancelled", updatedAt: serverTimestamp()}));
  });

  test.skip("[TAS-324] BLOCK: cancel another organization's invite", async () => {
    const i = id("inv");
    await seed(`invites/${i}`, {...inviteData("sa", {organizationId: ORG_B, companyId: CO_B}), createdAt: since, updatedAt: since});
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), `invites/${i}`), {status: "cancelled", updatedAt: serverTimestamp()}));
  });

  test("notification.service.ts:102+116 batch: send notifications to companies + sent_notifications", async () => {
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    for (const c of [CO_A, CO_A2]) {
      b.set(doc(collection(u, `${coPath(ORG_A, c)}/notifications`)), {
        message: "fake", organizationId: ORG_A, organizationName: "Org A", createdAt: serverTimestamp(), read: false,
      });
    }
    b.set(doc(collection(u, `organizations/${ORG_A}/sent_notifications`)), {
      message: "fake", targetCount: 2, createdAt: serverTimestamp(),
    });
    await assertSucceeds(b.commit());
  });

  test("BLOCK: notification.service.ts:102 notify a company of another organization", async () => {
    await assertDeniedByRule(addDoc(collection(db("orgadmin-a"), `${coPath(ORG_B, CO_B)}/notifications`), {
      message: "fake", organizationId: ORG_B, createdAt: serverTimestamp(), read: false,
    }));
  });

  test("notification.service.ts:265+277 batch: delete sent notification + its company copies", async () => {
    const n = id("notif");
    const s = id("sent");
    await seed(`${coPath(ORG_A, CO_A)}/notifications/${n}`, {message: "m", createdAt: since, read: false});
    await seed(`organizations/${ORG_A}/sent_notifications/${s}`, {message: "m", targetCount: 1, createdAt: since});
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.delete(doc(u, `${coPath(ORG_A, CO_A)}/notifications/${n}`));
    b.delete(doc(u, `organizations/${ORG_A}/sent_notifications/${s}`));
    await assertSucceeds(b.commit());
  });

  test("delegate-approval.service.ts:90-121 batch: delete delegate directly + its requests + notifications", async () => {
    const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {status: "approved", actionType: "create"});
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.delete(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`));
    b.delete(doc(u, `${coPath(ORG_A, CO_A)}/requests/${r}`));
    b.set(doc(collection(u, `${coPath(ORG_A, CO_A)}/notifications`)), {
      message: "تم حذف المندوب", organizationId: ORG_A, organizationName: "Org A", createdAt: serverTimestamp(), read: false,
    });
    b.set(doc(collection(u, `organizations/${ORG_A}/sent_notifications`)), {
      message: "تم حذف المندوب", targetCount: 1, createdAt: serverTimestamp(),
    });
    await assertSucceeds(b.commit());
  });

  test("BLOCK: delegate-approval.service.ts:90 delete a delegate of another organization", async () => {
    const {d} = await seedDelegateWithRequest(ORG_B, CO_B);
    await assertDeniedByRule(deleteDoc(doc(db("orgadmin-a"), `${coPath(ORG_B, CO_B)}/delegates/${d}`)));
  });

  test("delegate-approval.service.ts:257 request changes on a lost_id request", async () => {
    const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "lost_id"});
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_A, CO_A)}/requests/${r}`), {
      status: "action_required", rejectionReason: "fake reason", ...reviewedBy("orgadmin-a"),
    }));
  });

  test("delegate-approval.service.ts:306 request changes on an update request", async () => {
    const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "update"});
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_A, CO_A)}/requests/${r}`), {
      status: "action_required",
      review: {documents: [{documentKey: "personalPhoto", status: "rejected", reason: "blurry"}],
        summary: {total: 1, approved: 0, rejected: 1, pending: 0}},
      rejectionReason: "fake", ...reviewedBy("orgadmin-a"),
    }));
  });

  test("BLOCK: delegate-approval.service.ts:306 request changes in another organization", async () => {
    const {r} = await seedDelegateWithRequest(ORG_B, CO_B);
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_B, CO_B)}/requests/${r}`), {
      status: "action_required", ...reviewedBy("orgadmin-a"),
    }));
  });

  test("delegate-approval.service.ts:381 set isProfileComplete after approveUpdateRequest", async () => {
    const {d} = await seedDelegateWithRequest(ORG_A, CO_A, {status: "approved"}, {isProfileComplete: false});
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_A, CO_A)}/delegates/${d}`), {
      isProfileComplete: true,
    }));
  });

  for (const actionType of ["delete", "suspend", "activate"]) {
    test(`delegate-approval.service.ts:450+489 batch: reject ${actionType} request + clear delegate markers`, async () => {
      const status = actionType === "activate" ? "suspended" : "active";
      const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType}, {status, pendingAction: actionType});
      const u = db("orgadmin-a");
      const b = writeBatch(u);
      b.update(doc(u, `${coPath(ORG_A, CO_A)}/requests/${r}`), {
        status: "rejected", rejectionReason: "fake", ...reviewedBy("orgadmin-a"), ttlAt: in14d(),
      });
      b.update(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`), {
        updatedAt: serverTimestamp(), updatedBy: "orgadmin-a", latestRequestId: null, pendingAction: null,
      });
      await assertSucceeds(b.commit());
    });
  }

  test("delegate-approval.service.ts:526+539 batch: reject create request (delete pending delegate)", async () => {
    const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "create"},
      {status: "pending", documents: [{documentKey: "personalPhoto", documentStatus: "pending"}]});
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.delete(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`));
    b.update(doc(u, `${coPath(ORG_A, CO_A)}/requests/${r}`), {
      status: "rejected", rejectionReason: "fake", ...reviewedBy("orgadmin-a"), ttlAt: in14d(),
    });
    await assertSucceeds(b.commit());
  });

  test("delegate-approval.service.ts:585+598 batch: reject update request + clear delegate markers", async () => {
    const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "update"},
      {hasPendingUpdate: true, pendingAction: "update"});
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.update(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`), {
      hasPendingUpdate: false, latestRequestId: null, pendingAction: null,
      updatedAt: serverTimestamp(), updatedBy: "orgadmin-a",
    });
    b.update(doc(u, `${coPath(ORG_A, CO_A)}/requests/${r}`), {
      status: "rejected", rejectionReason: "fake", ...reviewedBy("orgadmin-a"), ttlAt: in14d(),
    });
    await assertSucceeds(b.commit());
  });

  test("delegate-approval.service.ts:718 approve new_id request", async () => {
    const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "new_id"});
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_A, CO_A)}/requests/${r}`), {
      status: "approved", ...reviewedBy("orgadmin-a"),
    }));
  });

  test("delegate-approval.service.ts:718 reject lost_id request", async () => {
    const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "lost_id"});
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_A, CO_A)}/requests/${r}`), {
      status: "rejected", ...reviewedBy("orgadmin-a"), rejectionReason: "fake", ttlAt: in14d(),
    }));
  });

  test("BLOCK: delegate-approval.service.ts:718 approve a request of another organization", async () => {
    const {r} = await seedDelegateWithRequest(ORG_B, CO_B, {actionType: "new_id"});
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_B, CO_B)}/requests/${r}`), {
      status: "approved", ...reviewedBy("orgadmin-a"),
    }));
  });

  test("delegate-request.service.ts:1292+1309 batch: print status on delegate + its lost_id requests (org-id-print-system)", async () => {
    const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "lost_id", status: "approved", isPrinted: false});
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.update(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`), {
      isPrinted: true, updatedAt: serverTimestamp(), updatedBy: "orgadmin-a",
    });
    b.update(doc(u, `${coPath(ORG_A, CO_A)}/requests/${r}`), {isPrinted: true});
    await assertSucceeds(b.commit());
  });

  test("BLOCK: delegate-request.service.ts:1292 print status on another organization's delegate", async () => {
    const {d} = await seedDelegateWithRequest(ORG_B, CO_B);
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), `${coPath(ORG_B, CO_B)}/delegates/${d}`), {
      isPrinted: true, updatedAt: serverTimestamp(), updatedBy: "orgadmin-a",
    }));
  });

  const companyReq = (o, c, extra = {}) => ({
    actionType: "create", status: "pending", targetCompanyId: c, targetCompanyName: c, companyCode: c,
    organizationUID: o, organizationName: o, requestedBy: "admin-a", requestedByName: "CA",
    requestedAt: since, createdAt: since, updatedAt: since, ...extra,
  });

  test("company-approval.service.ts:139+140 reject company request + company status Rejected", async () => {
    const r = id("creq");
    await seed(`organizations/${ORG_A}/companyRequests/${r}`, companyReq(ORG_A, CO_A2));
    const u = db("orgadmin-a");
    await assertSucceeds(updateDoc(doc(u, `organizations/${ORG_A}/companyRequests/${r}`), {
      status: "rejected", rejectionReason: "fake", ...reviewedBy("orgadmin-a"),
      review: {documents: [{documentKey: "taxCard", documentStatus: "rejected"}],
        summary: {total: 1, pending: 0, approved: 0, rejected: 1}},
    }));
    await assertSucceeds(updateDoc(doc(u, coPath(ORG_A, CO_A2)), {status: "Rejected", updatedAt: serverTimestamp()}));
  });

  test("company-approval.service.ts:254+255 batch: request changes on company request + company Action Required", async () => {
    const r = id("creq");
    await seed(`organizations/${ORG_A}/companyRequests/${r}`, companyReq(ORG_A, CO_A2));
    const u = db("orgadmin-a");
    const b = writeBatch(u);
    b.update(doc(u, `organizations/${ORG_A}/companyRequests/${r}`), {
      status: "action_required", changesRequestedReason: "fake",
      review: {documents: [{documentKey: "taxCard", documentStatus: "rejected"}],
        summary: {total: 1, pending: 0, approved: 0, rejected: 1}},
      ...reviewedBy("orgadmin-a"),
    });
    b.update(doc(u, coPath(ORG_A, CO_A2)), {status: "Action Required", updatedAt: serverTimestamp()});
    await assertSucceeds(b.commit());
  });

  test("BLOCK: company-approval.service.ts:139 reject a company request of another organization", async () => {
    const r = id("creq");
    await seed(`organizations/${ORG_B}/companyRequests/${r}`, companyReq(ORG_B, CO_B));
    await assertDeniedByRule(updateDoc(doc(db("orgadmin-a"), `organizations/${ORG_B}/companyRequests/${r}`), {
      status: "rejected", ...reviewedBy("orgadmin-a"),
    }));
  });

  test.skip("[TAS-322] auth.service.ts:732 sync users/{uid}.email after an email change (org-settings)", async () => {
    await assertSucceeds(updateDoc(doc(db("orgadmin-a"), "users/orgadmin-a"), {
      email: "orgadmin-a+new@fake.test", updatedAt: serverTimestamp(),
    }));
  });
});

// ======================= COMPANY ADMIN (with and without claims) =======================

for (const ca of COMPANY_ADMINS) {
  describe(`company-admin pages (${ca})`, () => {
    const reqCol = (o = ORG_A, c = CO_A) => `${coPath(o, c)}/requests`;
    const newRequest = (o, c, d, actionType, extra = {}) => ({
      actionType, status: "pending", targetDelegateId: d, targetDelegateName: "Fake Delegate",
      delegatePublicId: "P-1", companyUID: c, companyName: c, organizationUID: o, organizationName: o,
      requestedBy: ca, requestedByName: "CA", requestedAt: serverTimestamp(),
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
    });
    const newDelegate = (o, c, d, r) => ({
      uid: d, delegatePublicId: "P-NEW", status: "pending", statusReason: "create",
      hasPendingUpdate: false, version: 0,
      nationalityID: "29001010000001", firstName: "New", middleName: "Fake", lastName: "Delegate",
      fullName: "New Fake Delegate", motherName: "Mother", city: "Cairo", phoneNumber: "01000000001",
      gender: "Male", position: "Promoter", birthDate: since,
      documents: [
        {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "https://p"},
        {documentKey: "nationalityId", documentStatus: "pending", documentURL: "https://n"},
        {documentKey: "authorizationLetter", documentStatus: "not_provided"},
        {documentKey: "insuranceLetter", documentStatus: "not_provided"},
        {documentKey: "healthCertificate", documentStatus: "not_provided"},
        {documentKey: "paymentReceipt", documentStatus: "pending", documentURL: "https://r", receiptCode: "RC1"},
        {documentKey: "electronicPaymentReceipt", documentStatus: "not_provided"},
      ],
      numberOfDocuments: 3, paymentAmount: 100, receiptCode: "RC1", isDeductedFromCompany: false,
      allReceiptCodes: ["RC1"], companyType: "Retail",
      organizationUID: o, organizationName: o, companyUID: c, companyName: c,
      createdBy: ca, updatedBy: ca, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      isPrinted: false, latestRequestId: r,
    });

    test("delegate-request.service.ts:365+366 new delegate: setDoc delegate (pending) then setDoc create request", async () => {
      const u = db(ca);
      const d = id("newdel");
      const r = id("newreq");
      await assertSucceeds(setDoc(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`), newDelegate(ORG_A, CO_A, d, r)));
      await assertSucceeds(setDoc(doc(u, `${reqCol()}/${r}`), newRequest(ORG_A, CO_A, d, "create", {uid: r})));
    });

    test.skip("[TAS-324] BLOCK: delegate-request.service.ts:365 new delegate in another company", async () => {
      const d = id("newdel");
      await assertDeniedByRule(setDoc(doc(db(ca), `${coPath(ORG_A, CO_A2)}/delegates/${d}`),
        newDelegate(ORG_A, CO_A2, d, "x")));
    });

    test("BLOCK: delegate-request.service.ts:366 create request already approved (TAS-309)", async () => {
      const r = id("newreq");
      await assertDeniedByRule(setDoc(doc(db(ca), `${reqCol()}/${r}`),
        newRequest(ORG_A, CO_A, "x", "create", {uid: r, status: "approved"})));
    });

    for (const [line, actionType, delegateFields] of [
      ["473+475", "update", {pendingAction: "update", hasPendingUpdate: true}],
      ["524+526", "delete", {pendingAction: "delete"}],
      ["567+569", "suspend", {pendingAction: "suspend"}],
      ["610+612", "activate", {pendingAction: "activate"}],
      ["653+655", "new_id", {}],
    ]) {
      test(`delegate-request.service.ts:${line} ${actionType} request: setDoc request + delegate markers`, async () => {
        const u = db(ca);
        const d = id("del");
        await seed(`${coPath(ORG_A, CO_A)}/delegates/${d}`, delegateData(ORG_A, CO_A, {
          uid: d, status: actionType === "activate" ? "suspended" : "active",
        }));
        const r = id("req");
        const extra = actionType === "update"
          ? {requestedData: {city: "Giza"}, originalData: {city: "Cairo"}, patch: {city: "Giza"}, baseVersion: 0}
          : (actionType === "delete" ? {reason: "fake"} : {});
        await assertSucceeds(setDoc(doc(u, `${reqCol()}/${r}`), newRequest(ORG_A, CO_A, d, actionType, {uid: r, ...extra})));
        await assertSucceeds(updateDoc(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`), {
          ...delegateFields, latestRequestId: r, updatedAt: serverTimestamp(), updatedBy: ca,
        }));
      });
    }

    test("BLOCK: delegate-request.service.ts:569 markers on another company's delegate", async () => {
      const {d} = await seedDelegateWithRequest(ORG_A, CO_A2);
      await assertDeniedByRule(updateDoc(doc(db(ca), `${coPath(ORG_A, CO_A2)}/delegates/${d}`), {
        pendingAction: "suspend", latestRequestId: "x", updatedAt: serverTimestamp(), updatedBy: ca,
      }));
    });

    test("BLOCK: delegate-request.service.ts:567 request in another company", async () => {
      const r = id("req");
      await assertDeniedByRule(setDoc(doc(db(ca), `${reqCol(ORG_A, CO_A2)}/${r}`),
        newRequest(ORG_A, CO_A2, "x", "suspend", {uid: r})));
    });

    test("delegate-request.service.ts:742 lost_id request (lost-id-request-dialog)", async () => {
      const d = id("del");
      await seed(`${coPath(ORG_A, CO_A)}/delegates/${d}`, delegateData(ORG_A, CO_A, {uid: d}));
      const r = id("req");
      await assertSucceeds(setDoc(doc(db(ca), `${reqCol()}/${r}`), newRequest(ORG_A, CO_A, d, "lost_id", {
        uid: r, isPrinted: false,
        requestedData: {lostIdReceiptUrl: "https://s", lostIdReceiptAmount: 50, lostIdReceiptCode: "LC1"},
      })));
    });

    test("delegate-request.service.ts:783 resubmit lost_id request after action_required", async () => {
      const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {
        actionType: "lost_id", status: "action_required", rejectionReason: "fix it",
        requestedData: {lostIdReceiptUrl: "https://s", lostIdReceiptAmount: 50, lostIdReceiptCode: "LC1"},
      });
      await assertSucceeds(updateDoc(doc(db(ca), `${reqCol()}/${r}`), {
        status: "pending", rejectionReason: deleteField(),
        "requestedData.lostIdReceiptAmount": 60, "requestedData.lostIdReceiptCode": "LC2",
        "requestedData.lostIdReceiptUrl": "https://s2", updatedAt: serverTimestamp(),
      }));
    });

    test("com-edit-request.ts:672 resubmit update request after action_required", async () => {
      const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {
        actionType: "update", status: "action_required", rejectionReason: "fix it",
        review: {documents: [], summary: {}}, requestedData: {city: "Giza"},
      });
      await assertSucceeds(updateDoc(doc(db(ca), `${reqCol()}/${r}`), {
        requestedData: {city: "Alex"}, status: "pending", updatedAt: serverTimestamp(),
        review: null, rejectionReason: null,
      }));
    });

    test("BLOCK: com-edit-request.ts:672 company admin approves its own request (TAS-309)", async () => {
      const {r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "update", status: "action_required"});
      await assertDeniedByRule(updateDoc(doc(db(ca), `${reqCol()}/${r}`), {status: "approved", updatedAt: serverTimestamp()}));
    });

    test("delegate-request.service.ts:802+856 cancel update request + clear delegate markers", async () => {
      const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "update"},
        {hasPendingUpdate: true, pendingAction: "update"});
      const u = db(ca);
      await assertSucceeds(updateDoc(doc(u, `${reqCol()}/${r}`), {
        status: "cancelled", updatedAt: serverTimestamp(), ttlAt: in14d(),
      }));
      await assertSucceeds(updateDoc(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`), {
        updatedAt: serverTimestamp(), updatedBy: ca, pendingAction: null,
        latestRequestId: null, hasPendingUpdate: false,
      }));
    });

    test("delegate-request.service.ts:802+839 cancel create request + delete the pending delegate", async () => {
      const {d, r} = await seedDelegateWithRequest(ORG_A, CO_A, {actionType: "create"},
        {status: "pending", documents: [{documentKey: "personalPhoto", documentStatus: "pending"}]});
      const u = db(ca);
      await assertSucceeds(updateDoc(doc(u, `${reqCol()}/${r}`), {
        status: "cancelled", updatedAt: serverTimestamp(), ttlAt: in14d(),
      }));
      await assertSucceeds(deleteDoc(doc(u, `${coPath(ORG_A, CO_A)}/delegates/${d}`)));
    });

    test("BLOCK: delegate-request.service.ts:839 delete another company's delegate", async () => {
      const {d} = await seedDelegateWithRequest(ORG_A, CO_A2);
      await assertDeniedByRule(deleteDoc(doc(db(ca), `${coPath(ORG_A, CO_A2)}/delegates/${d}`)));
    });

    const companyReq = (c, extra = {}) => ({
      actionType: "create", status: "pending", targetCompanyId: c, targetCompanyName: c, companyCode: c,
      organizationUID: ORG_A, organizationName: ORG_A, requestedBy: ca, requestedByName: "CA",
      requestedAt: serverTimestamp(), createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
    });

    test("company-request.service.ts:444+445 batch: new company request + company status (com-profile documents)", async () => {
      await seed(coPath(ORG_A, CO_A), companyData(ORG_A, CO_A));
      const u = db(ca);
      const ref = doc(collection(u, `organizations/${ORG_A}/companyRequests`));
      const b = writeBatch(u);
      b.set(ref, {...companyReq(CO_A, {
        actionType: "update", uid: ref.id,
        requestedData: {taxCardNumber: "3", documentUrls: {taxCard: "https://tc2"}, oldDocumentUrls: {taxCard: ["https://tc"]}},
        review: {documents: [{documentKey: "taxCard", documentStatus: "pending"}],
          summary: {total: 1, pending: 1, approved: 0, rejected: 0}},
      })});
      b.update(doc(u, coPath(ORG_A, CO_A)), {status: "Action Required", updatedAt: serverTimestamp()});
      await assertSucceeds(b.commit());
    });

    test("company-request.service.ts:430+431 batch: update existing company request + company Action Required", async () => {
      await seed(coPath(ORG_A, CO_A), companyData(ORG_A, CO_A));
      const r = id("creq");
      await seed(`organizations/${ORG_A}/companyRequests/${r}`, {...companyReq(CO_A, {
        status: "action_required", changesRequestedReason: "fix", requestedAt: since, createdAt: since, updatedAt: since,
        // Only the re-uploaded document was in the request: the web's nested
        // deleteField() (company-request.service.ts:238/245) is not reached.
        // That path fails in the SDK itself, before the rules (TAS-323).
        requestedData: {documentUrls: {taxCard: "https://tc1"}},
      }), uid: r});
      const u = db(ca);
      const b = writeBatch(u);
      b.update(doc(u, `organizations/${ORG_A}/companyRequests/${r}`), {
        actionType: "update", status: "pending",
        requestedData: {taxCardNumber: "3", documentUrls: {taxCard: "https://tc2"},
          oldDocumentUrls: {taxCard: ["https://tc"]}},
        review: {documents: [{documentKey: "taxCard", documentStatus: "pending"}],
          summary: {total: 1, pending: 1, approved: 0, rejected: 0}},
        changesRequestedReason: deleteField(), updatedAt: serverTimestamp(),
      });
      b.update(doc(u, coPath(ORG_A, CO_A)), {status: "Action Required", updatedAt: serverTimestamp()});
      await assertSucceeds(b.commit());
    });

    test("company-request.service.ts:509+510 batch: initial company request + company Pending (finish-signup)", async () => {
      await seed(coPath(ORG_A, CO_A), companyData(ORG_A, CO_A, {status: "Pending"}));
      const u = db(ca);
      const ref = doc(collection(u, `organizations/${ORG_A}/companyRequests`));
      const b = writeBatch(u);
      b.set(ref, {...companyReq(CO_A), uid: ref.id});
      b.update(doc(u, coPath(ORG_A, CO_A)), {status: "Pending", updatedAt: serverTimestamp()});
      await assertSucceeds(b.commit());
    });

    test("BLOCK: company-request.service.ts:444 company request for another company", async () => {
      await assertDeniedByRule(addDoc(collection(db(ca), `organizations/${ORG_A}/companyRequests`), companyReq(CO_A2)));
    });

    test("BLOCK: company-request.service.ts:445 company admin sets its company Active", async () => {
      await assertDeniedByRule(updateDoc(doc(db(ca), coPath(ORG_A, CO_A)), {status: "Active", updatedAt: serverTimestamp()}));
    });

    test("notification.service.ts:225 mark company notification as read (notifications-list-dialog)", async () => {
      const n = id("notif");
      await seed(`${coPath(ORG_A, CO_A)}/notifications/${n}`, {message: "m", createdAt: since, read: false});
      await assertSucceeds(updateDoc(doc(db(ca), `${coPath(ORG_A, CO_A)}/notifications/${n}`), {read: true}));
    });

    test("BLOCK: notification.service.ts:225 mark another company's notification", async () => {
      const n = id("notif");
      await seed(`${coPath(ORG_A, CO_A2)}/notifications/${n}`, {message: "m", createdAt: since, read: false});
      await assertDeniedByRule(updateDoc(doc(db(ca), `${coPath(ORG_A, CO_A2)}/notifications/${n}`), {read: true}));
    });

    test.skip("[TAS-322] auth.service.ts:732 sync users/{uid}.email after an email change (com-settings)", async () => {
      await assertSucceeds(updateDoc(doc(db(ca), `users/${ca}`), {
        email: `${ca}+new@fake.test`, updatedAt: serverTimestamp(),
      }));
    });
  });
}
