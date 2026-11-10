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
