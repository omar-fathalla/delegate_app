const test = require("node:test");
const assert = require("node:assert");
const L = require("../lib/delegate_profile_edit_logic");

test("editor and reviewer role gates", () => {
  assert.ok(L.isEditorRole("supervisor"));
  assert.ok(L.isEditorRole("company_supervisor"));
  assert.ok(L.isEditorRole("admin"));
  assert.ok(!L.isEditorRole("hr"));
  assert.ok(!L.isEditorRole("super-admin"));
  assert.ok(L.isReviewerRole("super-admin"));
  assert.ok(L.isReviewerRole("technicalSupport"));
  assert.ok(!L.isReviewerRole("supervisor"));
});

test("editable statuses", () => {
  assert.ok(L.isEditableRequestStatus("pending"));
  assert.ok(L.isEditableRequestStatus("action_required"));
  assert.ok(!L.isEditableRequestStatus("approved"));
  assert.ok(L.isEditableDelegateStatus("active"));
  assert.ok(L.isEditableDelegateStatus("approved"));
  assert.ok(!L.isEditableDelegateStatus("inactive"));
});

test("sanitizeProfileEdit drops empty values and splits names", () => {
  const {fields, keys} = L.sanitizeProfileEdit({
    fullName: "  أحمد علي حسن  ",
    phoneNumber: "",
    personalPhotoURL: "https://example.com/p.jpg",
  });
  assert.deepStrictEqual(keys, ["fullName", "personalPhotoURL"]);
  assert.strictEqual(fields.fullName, "أحمد علي حسن");
  const parts = L.splitFullName(fields.fullName);
  assert.strictEqual(parts.firstName, "أحمد");
  assert.strictEqual(parts.lastName, "حسن");
  assert.strictEqual(parts.secondName, "علي");
});

test("shouldAlertAdmins only for name and ID images", () => {
  assert.ok(L.shouldAlertAdmins(["fullName"]));
  assert.ok(L.shouldAlertAdmins(["nationalIdFrontUrl"]));
  assert.ok(L.shouldAlertAdmins(["phoneNumber", "nationalIdBackUrl"]));
  assert.ok(!L.shouldAlertAdmins(["phoneNumber"]));
  assert.ok(!L.shouldAlertAdmins(["personalPhotoURL"]));
});

test("applyProfileFields updates name parts, phone, photos, and documents", () => {
  const patch = L.applyProfileFields({
    fullName: "قديم",
    phoneNumber: "0100",
    documents: [{documentKey: "personalPhoto", documentURL: "old", documentStatus: "approved"}],
  }, {fullName: "أحمد علي حسن", phoneNumber: "0111", personalPhotoURL: "new.jpg"});
  assert.strictEqual(patch.fullName, "أحمد علي حسن");
  assert.strictEqual(patch.firstName, "أحمد");
  assert.strictEqual(patch.phoneNumber, "0111");
  assert.strictEqual(patch.personalPhotoURL, "new.jpg");
  assert.strictEqual(patch.profileImageUrl, "new.jpg");
  const photo = patch.documents.find((d) => d.documentKey === "personalPhoto");
  assert.strictEqual(photo.documentURL, "new.jpg");
  assert.strictEqual(photo.documentStatus, "approved");
});

test("auditDoc is limited to actor, field, values, and identifiers", () => {
  const rec = L.auditDoc({
    actorUid: "u1",
    actorName: "مشرف",
    actorRole: "supervisor",
    field: "nationalIdFrontUrl",
    oldValue: "old",
    newValue: "new",
    delegateUid: "d1",
    delegateName: "مندوب",
    companyUID: "c1",
    companyName: "شركة",
    organizationUID: "o1",
    source: "direct_edit",
  });
  assert.strictEqual(rec.fieldLabel, "صورة البطاقة الأمامية");
  assert.strictEqual(rec.isImage, true);
  assert.deepStrictEqual(Object.keys(rec).sort(), [
    "actorName", "actorRole", "actorUid", "companyName", "companyUID",
    "delegateName", "delegateUid", "field", "fieldLabel", "isImage",
    "newValue", "oldValue", "organizationUID", "source",
  ]);
});

test("companyScopeDecision requires a caller companyUID (M-2)", () => {
  assert.strictEqual(L.companyScopeDecision("", "c1"), "missing-company");
  assert.strictEqual(L.companyScopeDecision("c2", "c1"), "mismatch");
  assert.strictEqual(L.companyScopeDecision("c1", "c1"), "ok");
});

test("isPatchableTarget skips legacy and other-company paths (M-3)", () => {
  assert.ok(L.isPatchableTarget("c1", {companyUID: "c1"}, "organizations/o1/companies/c1/delegates/d1"));
  assert.ok(!L.isPatchableTarget("c1", {}, "organizations/o3/companies/c2/delegates/d1"));
  assert.ok(!L.isPatchableTarget("c1", {companyUID: "c1"}, "organizations/o3/companies/c2/delegates/d1"));
  assert.ok(!L.isPatchableTarget("c1", {companyUID: "c2"}, "organizations/o1/companies/c1/delegates/d1"));
});

test("isAllowedImageUrl accepts storage URLs/paths and rejects javascript (LOW)", () => {
  assert.ok(L.isAllowedImageUrl("https://firebasestorage.googleapis.com/v0/b/tashil-dev.appspot.com/o/x"));
  assert.ok(L.isAllowedImageUrl("delegate_documents/d1/profile_1.jpg", "d1"));
  assert.ok(!L.isAllowedImageUrl("javascript:alert(1)"));
  assert.ok(!L.isAllowedImageUrl("http://example.com/x.jpg"));
  assert.ok(!L.isAllowedImageUrl("delegate_documents/other/x.jpg", "d1"));
  assert.throws(() => L.assertImageFields({personalPhotoURL: "javascript:alert(1)"}), /invalid-image-url/);
  assert.ok(L.isAllowedImageUrl("https://firebasestorage.googleapis.com/v0/b/tashil-dev.firebasestorage.app/o/x"));
  assert.ok(L.isAllowedImageUrl("https://firebasestorage.googleapis.com/v0/b/practice-firebase-72df1.appspot.com/o/x"));
  assert.ok(L.isAllowedImageUrl("https://practice-firebase-72df1.firebasestorage.app/v0/b/practice-firebase-72df1.firebasestorage.app/o/x")
    || L.isAllowedImageUrl("https://tashil-dev.firebasestorage.app/o/x"));
  assert.ok(L.isAllowedImageUrl("https://tashil-dev.firebasestorage.app/o/x"));
  assert.ok(!L.isAllowedImageUrl("https://evil.appspot.com/x.png"));
  assert.ok(!L.isAllowedImageUrl("https://firebasestorage.googleapis.com/v0/b/evil.appspot.com/o/x"));
  assert.ok(!L.isAllowedImageUrl("https://storage.googleapis.com/evil.appspot.com/x"));
  assert.ok(!L.isAllowedImageUrl("https://attacker.firebasestorage.app/o/x"));
});

test("reviewTargetMatchesSubmission verifies the submitted delegate (N-1)", () => {
  const path = "organizations/o1/companies/c1/delegates/d1";
  const ok = {uid: "d1", companyUID: "c1", status: "active"};
  assert.equal(L.reviewTargetMatchesSubmission({
    requestDelegateUid: "d1", requestCompanyUID: "c1",
    liveExists: true, livePath: path, liveData: ok,
  }), "ok");
  assert.equal(L.reviewTargetMatchesSubmission({
    requestDelegateUid: "d1", requestCompanyUID: "c1",
    liveExists: true, livePath: path, liveData: {uid: "dsusp", companyUID: "c1", status: "active"},
  }), "mismatch");
  assert.equal(L.reviewTargetMatchesSubmission({
    requestDelegateUid: "d1", requestCompanyUID: "c1",
    liveExists: true, livePath: "organizations/o1/companies/c2/delegates/d1",
    liveData: {uid: "d1", companyUID: "c1", status: "active"},
  }), "mismatch");
  assert.equal(L.reviewTargetMatchesSubmission({
    requestDelegateUid: "d1", requestCompanyUID: "c1",
    liveExists: true, livePath: path, liveData: {uid: "d1", companyUID: "c1", status: "suspended"},
  }), "inactive");
  assert.equal(L.reviewTargetMatchesSubmission({
    requestDelegateUid: "d1", requestCompanyUID: "c1",
    liveExists: false, livePath: path,
  }), "missing");
});

test("usersProfileSyncPatch copies name, phone and photo (N-5)", () => {
  const patch = L.usersProfileSyncPatch({
    fullName: "محمد علي حسن",
    phoneNumber: "01012345678",
    personalPhotoURL: "https://tashil-dev.firebasestorage.app/o/p.jpg",
  });
  assert.equal(patch.fullName, "محمد علي حسن");
  assert.equal(patch.phoneNumber, "01012345678");
  assert.equal(patch.phone, "01012345678");
  assert.equal(patch.personalPhotoURL, "https://tashil-dev.firebasestorage.app/o/p.jpg");
  assert.equal(L.usersProfileSyncPatch({}), null);
});

test("privileged alert role list includes compacted spellings (N-4)", () => {
  assert.ok(L.PRIVILEGED_ALERT_ROLE_VALUES.includes("superadmin"));
  assert.ok(L.PRIVILEGED_ALERT_ROLE_VALUES.includes("technicalsupport"));
  assert.ok(L.PRIVILEGED_ALERT_ROLE_VALUES.includes("super-admin"));
  assert.ok(L.PRIVILEGED_ALERT_ROLE_VALUES.includes("technical_support"));
});

test("privilegedAlertDoc writes one recipient and no phoneNumber (M-7)", () => {
  const rec = L.privilegedAlertDoc({
    recipientUid: "sa1",
    title: "تعديل",
    body: "جسم",
    type: "delegate_profile_edit",
    senderName: "مشرف",
    senderRole: "supervisor",
    companyUID: "c1",
    organizationUID: "o1",
    targetDelegateUid: "d1",
  });
  assert.strictEqual(rec.delegateUid, "sa1");
  assert.strictEqual(rec.targetDelegateUid, "d1");
  assert.ok(!Object.prototype.hasOwnProperty.call(rec, "phoneNumber"));
  assert.deepStrictEqual(L.uniqueRecipientIds(["sa1", "sa1", "ts1", ""]), ["sa1", "ts1"]);
});

test("supervisorReviewAlertDoc covers approve and reject (M-8)", () => {
  const ok = L.supervisorReviewAlertDoc({
    supervisorUid: "sup1",
    approved: true,
    reviewerName: "إدارة",
    delegateName: "مندوب",
    companyUID: "c1",
    organizationUID: "o1",
    requestId: "r1",
    targetDelegateUid: "d1",
  });
  assert.strictEqual(ok.delegateUid, "sup1");
  assert.strictEqual(ok.type, "delegate_national_id_review");
  assert.ok(!Object.prototype.hasOwnProperty.call(ok, "phoneNumber"));
  const no = L.supervisorReviewAlertDoc({
    supervisorUid: "sup1",
    approved: false,
    reviewerName: "دعم",
    delegateName: "مندوب",
    companyUID: "c1",
    organizationUID: "o1",
    requestId: "r1",
    targetDelegateUid: "d1",
    rejectionReason: "غير واضح",
  });
  assert.match(no.title, /رفض/);
  assert.match(no.body, /غير واضح/);
});

test("auditDoc accepts a national_id_rejection source (M-8)", () => {
  const rec = L.auditDoc({
    actorUid: "sa",
    actorName: "إدارة",
    actorRole: "super-admin",
    field: "nationalId",
    oldValue: "29001010100011",
    newValue: "29001010100022",
    delegateUid: "d1",
    delegateName: "مندوب",
    companyUID: "c1",
    companyName: "شركة",
    organizationUID: "o1",
    source: "national_id_rejection",
    requestId: "r1",
  });
  assert.strictEqual(rec.source, "national_id_rejection");
  assert.strictEqual(rec.requestId, "r1");
});
