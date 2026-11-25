// TAS-331: Storage paths next to the delegate document URLs.
const {test} = require("node:test");
const assert = require("node:assert/strict");

const S = require("../lib/supervisor_delegate_doc_reupload_logic");
const P = require("../lib/privileged_delegate_doc_reupload_logic");
const E = require("../lib/delegate_profile_edit_logic");
const A = require("../lib/company_chain_autolink_logic");
const C = require("../lib/supervisor_cards_logic");

const BUCKET = "tashil-dev.firebasestorage.app";
const url = (path) =>
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(path)}?alt=media&token=t`;

test("supervisor merge writes documentPath next to the URL", () => {
  const raw = [{documentKey: "personalPhoto", documentStatus: "approved", documentURL: "old", documentPath: "delegate_documents/d1/old.jpg"}];
  const out = S.mergeReuploadedDocument(raw, "personalPhoto", "u-new", "t", "delegate_documents/d1/new.jpg");
  assert.equal(out[0].documentURL, "u-new");
  assert.equal(out[0].documentPath, "delegate_documents/d1/new.jpg");
  assert.equal(out[0].documentStatus, "pending");
});

test("a URL-only re-upload drops the stale path", () => {
  const raw = [{documentKey: "personalPhoto", documentStatus: "approved", documentURL: "old", documentPath: "delegate_documents/d1/old.jpg"}];
  const out = S.mergeReuploadedDocument(raw, "personalPhoto", "u-new", "t");
  assert.equal(out[0].documentURL, "u-new");
  assert.equal("documentPath" in out[0], false);
});

test("ID back goes to secondaryPath, front path kept", () => {
  const raw = [{documentKey: "nationalityId", documentStatus: "approved", documentURL: "f", documentPath: "delegate_documents/d1/f.jpg"}];
  const out = P.mergePrivilegedReuploadedDocument(raw, "nationalIdBack", "", "t", "sa", "delegate_documents/d1/b.jpg");
  assert.equal(out[0].secondaryURL, "");
  assert.equal(out[0].secondaryPath, "delegate_documents/d1/b.jpg");
  assert.equal(out[0].documentPath, "delegate_documents/d1/f.jpg");
  assert.equal(out[0].documentStatus, "approved");
});

test("pathFieldsForDocType: path or null (delete)", () => {
  assert.deepEqual(S.pathFieldsForDocType("personalPhoto", "delegate_documents/d1/p.jpg"), {profileImagePath: "delegate_documents/d1/p.jpg"});
  assert.deepEqual(S.pathFieldsForDocType("nationalIdFront", ""), {nationalIdFrontPath: null});
  assert.deepEqual(S.pathFieldsForDocType("paymentReceipt", "x/y"), {receiptImagePath: "x/y"});
  assert.deepEqual(S.pathFieldsForDocType("unknown", "x/y"), {});
});

test("resolveReuploadObject: own folder only, URL and path must match", () => {
  const p = "delegate_documents/d1/personalPhoto_1.jpg";
  assert.deepEqual(P.resolveReuploadObject("", p, "d1", BUCKET), {ok: true, objectPath: p});
  assert.deepEqual(P.resolveReuploadObject(url(p), p, "d1", BUCKET), {ok: true, objectPath: p});
  assert.equal(P.resolveReuploadObject("", "delegate_documents/d2/x.jpg", "d1", BUCKET).ok, false);
  assert.equal(P.resolveReuploadObject("", "delegate_documents/d1/../d2/x.jpg", "d1", BUCKET).ok, false);
  assert.equal(P.resolveReuploadObject("", "gs://other/delegate_documents/d1/x.jpg", "d1", BUCKET).ok, false);
  assert.equal(P.resolveReuploadObject("", "organizations/o1/companies/c2/x.jpg", "d1", BUCKET).ok, false);
  const mismatch = P.resolveReuploadObject(url("delegate_documents/d1/other.jpg"), p, "d1", BUCKET);
  assert.deepEqual(mismatch, {ok: false, reason: "url_path_mismatch"});
  // Old clients: URL only, unchanged behaviour.
  assert.equal(P.resolveReuploadObject(url(p), "", "d1", BUCKET).ok, true);
});

test("editDelegateProfile: a path-only image counts as the field", () => {
  const {fields, keys} = E.sanitizeProfileEdit({personalPhotoPath: " delegate_documents/d1/p.jpg "});
  assert.deepEqual(keys, ["personalPhotoURL"]);
  assert.equal(fields.personalPhotoPath, "delegate_documents/d1/p.jpg");
  assert.equal(E.imageRef(fields, "personalPhotoURL"), "delegate_documents/d1/p.jpg");
});

test("editDelegateProfile: patch writes URL + path, entries carry paths", () => {
  const current = {
    photoURL: "old",
    documents: [
      {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "old", documentPath: "delegate_documents/d1/old.jpg"},
      {documentKey: "nationalityId", documentStatus: "approved", documentURL: "f", secondaryURL: "b", secondaryPath: "delegate_documents/d1/b.jpg"},
    ],
  };
  const patch = E.applyProfileFields(current, {
    personalPhotoURL: "u", personalPhotoPath: "delegate_documents/d1/p.jpg",
    nationalIdFrontPath: "delegate_documents/d1/f2.jpg",
  });
  assert.equal(patch.profileImageUrl, "u");
  assert.equal(patch.photoURL, "u");
  assert.equal(patch.profileImagePath, "delegate_documents/d1/p.jpg");
  assert.equal(patch.nationalIdFrontUrl, "");
  assert.equal(patch.nationalIdFrontPath, "delegate_documents/d1/f2.jpg");
  assert.equal("nationalIdBackPath" in patch, false);
  const [photo, id] = patch.documents;
  assert.equal(photo.documentPath, "delegate_documents/d1/p.jpg");
  assert.equal(id.documentURL, "");
  assert.equal(id.documentPath, "delegate_documents/d1/f2.jpg");
  assert.equal(id.secondaryURL, "b");
  assert.equal(id.secondaryPath, "delegate_documents/d1/b.jpg");
});

test("editDelegateProfile: URL-only edit (old client) clears the stale path", () => {
  const current = {documents: [{documentKey: "personalPhoto", documentStatus: "approved", documentURL: "old", documentPath: "delegate_documents/d1/old.jpg"}]};
  const patch = E.applyProfileFields(current, {personalPhotoURL: "https://new"});
  assert.equal(patch.profileImagePath, null);
  assert.equal("documentPath" in patch.documents[0], false);
  assert.equal(patch.documents[0].documentURL, "https://new");
});

test("editDelegateProfile: paths must be inside the delegate's folder", () => {
  assert.doesNotThrow(() => E.assertImageFields({personalPhotoPath: "delegate_documents/d1/p.jpg"}, "d1"));
  assert.throws(() => E.assertImageFields({personalPhotoPath: "delegate_documents/d2/p.jpg"}, "d1"));
  assert.throws(() => E.assertImageFields({nationalIdBackPath: "https://x/y"}, "d1"));
  assert.throws(() => E.assertImageFields({nationalIdFrontPath: "delegate_documents/d1/../d2/a"}, "d1"));
});

test("users sync carries the photo path", () => {
  assert.deepEqual(E.usersProfileSyncPatch({personalPhotoPath: "delegate_documents/d1/p.jpg"}), {
    personalPhotoURL: "", profileImageUrl: "", photoURL: "", profileImagePath: "delegate_documents/d1/p.jpg",
  });
});

test("auto-link copies the path fields", () => {
  for (const k of ["profileImagePath", "nationalIdFrontPath", "nationalIdBackPath"]) {
    assert.ok(A.AUTO_LINK_COPY_FIELDS.includes(k), k);
  }
});

test("supervisor card falls back to the stored photo path", () => {
  assert.equal(C.toCard("u", {fullName: "A", profileImagePath: "delegate_documents/u/p.jpg"}).photoUrl, "delegate_documents/u/p.jpg");
  assert.equal(C.toCard("u", {fullName: "A", photoURL: "https://x", profileImagePath: "p/q"}).photoUrl, "https://x");
});

test("approveDelegateDocuments: entry paths must match the request's paths", () => {
  const AP = require("../lib/approve_delegate_documents_logic");
  const req = {
    profileImageUrl: "u1", nationalIdFrontUrl: "f", nationalIdBackUrl: "b",
    profileImagePath: "delegate_documents/d1/profile.jpg",
    nationalIdFrontPath: "delegate_documents/d1/front.jpg",
    nationalIdBackPath: "delegate_documents/d1/back.jpg",
  };
  const urls = AP.requestUrlMap(req);
  const doc = (docs) => ({status: "pending", companyUID: "c1", organizationUID: "o1", documents: docs});
  const ok = AP.planActivation("o1", "c1", "d1", doc([
    {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "u1", documentPath: "delegate_documents/d1/profile.jpg"},
    {documentKey: "nationalityId", documentStatus: "pending", documentURL: "f", secondaryURL: "b",
      documentPath: "delegate_documents/d1/front.jpg", secondaryPath: "delegate_documents/d1/back.jpg"},
  ]), urls, "r", "t");
  assert.equal(ok.ok, true);
  assert.equal(ok.flipped, 2);
  // Entry without a path (older app) still flips.
  assert.equal(AP.planActivation("o1", "c1", "d1", doc([
    {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "u1"},
  ]), urls, "r", "t").ok, true);
  // A different path is refused.
  const bad = AP.planActivation("o1", "c1", "d1", doc([
    {documentKey: "nationalityId", documentStatus: "pending", documentURL: "f", secondaryURL: "b",
      documentPath: "delegate_documents/d1/front.jpg", secondaryPath: "delegate_documents/d2/back.jpg"},
  ]), urls, "r", "t");
  assert.equal(bad.ok, false);
  // A path on a request written before TAS-331 (no paths) is refused too.
  const old = AP.requestUrlMap({profileImageUrl: "u1"});
  assert.equal(AP.planActivation("o1", "c1", "d1", doc([
    {documentKey: "personalPhoto", documentStatus: "pending", documentURL: "u1", documentPath: "delegate_documents/d1/x.jpg"},
  ]), old, "r", "t").ok, false);
  // A '#p' key is never a document key.
  assert.equal(AP.planActivation("o1", "c1", "d1", doc([
    {documentKey: "personalPhoto#p", documentStatus: "pending", documentURL: "delegate_documents/d1/profile.jpg"},
  ]), urls, "r", "t").ok, false);
});
