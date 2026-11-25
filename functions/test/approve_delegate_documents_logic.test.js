// TAS-336: pure checks of approveDelegateDocuments (mirror of firestore.rules).
const {test} = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/approve_delegate_documents_logic");

const req = (over = {}) => ({
  status: "pending",
  requestType: "new_delegate",
  supervisorUid: "sup",
  companyUID: "c1",
  organizationUID: "o1",
  organizationUIDs: ["o1", "o2"],
  profileImageUrl: "p0",
  nationalIdFrontUrl: "f0",
  nationalIdBackUrl: "b0",
  receiptImageUrl: "r0",
  orgCompanyCheck: "ok",
  ...over,
});

const pend = (key, url, extra = {}) => ({documentKey: key, documentStatus: "pending", documentURL: url, ...extra});
const doc = (docs, over = {}) => ({status: "pending", companyUID: "c1", organizationUID: "o1", documents: docs, ...over});

test("role comes from claims only", () => {
  assert.equal(L.approverRoleFromClaims({role: "super-admin"}), "super_admin");
  assert.equal(L.approverRoleFromClaims({role: "Super_Admin "}), "super_admin");
  assert.equal(L.approverRoleFromClaims({role: "technical_support"}), "tech_support");
  assert.equal(L.approverRoleFromClaims({role: "techSupport"}), "tech_support");
  assert.equal(L.approverRoleFromClaims({role: "supervisor"}), null);
  assert.equal(L.approverRoleFromClaims({role: "organization-admin"}), null);
  assert.equal(L.approverRoleFromClaims({}), null);
  assert.equal(L.approverRoleFromClaims(null), null);
});

test("parseInput validates request id and targets", () => {
  assert.equal(L.parseInput({}).ok, false);
  assert.equal(L.parseInput({requestId: "a/b", organizationUIDs: ["o1"]}).ok, false);
  assert.equal(L.parseInput({requestId: "r1", organizationUIDs: []}).ok, false);
  assert.equal(L.parseInput({requestId: "r1", organizationUIDs: ["o/1"]}).ok, false);
  assert.equal(L.parseInput({requestId: "r1", organizationUIDs: new Array(21).fill("o")}).ok, false);
  const ok = L.parseInput({requestId: " r1 ", organizationUIDs: ["o1", "o1", "o2"], reviewerName: "TS"});
  assert.deepEqual(ok, {ok: true, value: {requestId: "r1", organizationUIDs: ["o1", "o2"], reviewerName: "TS"}});
});

test("checkRequest mirrors techRequestReviewOk / payment / org check", () => {
  assert.deepEqual(L.checkRequest("tech_support", "ts", "r1", req()), {ok: true});
  assert.equal(L.checkRequest("tech_support", "ts", "r1", req({status: "approved"})).reason, "request_not_pending");
  assert.equal(L.checkRequest("tech_support", "ts", "r1", req({status: "Pending"})).reason, "request_not_pending");
  assert.equal(L.checkRequest("tech_support", "sup", "r1", req()).reason, "own_request");
  assert.equal(L.checkRequest("tech_support", "ts", "r1", req({createdBy: "ts"})).reason, "own_request");
  // Super-admin is not bound by the own-request rule for supervisorUid.
  assert.deepEqual(L.checkRequest("super_admin", "sup", "r1", req()), {ok: true});
  // Nobody approves their own delegate doc.
  assert.equal(L.checkRequest("super_admin", "r1", "r1", req()).reason, "own_request");
  assert.equal(L.checkRequest("tech_support", "ts", "r1", req({requestType: "renewal"})).reason, "unsupported_request_type");
  assert.equal(L.checkRequest("tech_support", "ts", "r1",
    req({paymentMethod: "paymob", paymentStatus: "pending"})).reason, "payment_not_settled");
  assert.deepEqual(L.checkRequest("tech_support", "ts", "r1",
    req({paymentMethod: "paymob", paymentStatus: "paid"})), {ok: true});
  assert.equal(L.checkRequest("tech_support", "ts", "r1", req({orgCompanyCheck: "failed"})).reason,
    "org_company_check_not_ok");
  assert.equal(L.checkRequest("tech_support", "ts", "r1",
    req({requestType: "add_organization"})).reason, "no_bound_delegate");
  assert.deepEqual(L.checkRequest("tech_support", "ts", "r1",
    req({requestType: "add_organization", existingDelegateUid: "d9"})), {ok: true});
});

test("orgAllowed mirrors techReqOk", () => {
  assert.equal(L.orgAllowed("o1", req(), ""), true);
  assert.equal(L.orgAllowed("o2", req(), ""), true);
  assert.equal(L.orgAllowed("o3", req(), ""), false);
  assert.equal(L.orgAllowed("o3", req(), "o3"), true);
  const addOrg = req({requestType: "add_organization", existingDelegateUid: "d9"});
  assert.equal(L.orgAllowed("o2", addOrg, "o2"), false);
});

test("planActivation flips 8 pending entries with request URLs", () => {
  const urls = L.requestUrlMap(req());
  const docs = [
    pend("personalPhoto", "p0"), pend("nationalityId", "f0", {secondaryURL: "b0"}),
    pend("paymentReceipt", "r0"), pend("electronicPaymentReceipt", "r0"),
    pend("electronic_payment_receipt", "r0"), pend("personalPhoto", "p0"),
    pend("paymentReceipt", "r0"), {documentKey: "x", documentStatus: "rejected", documentURL: "z"},
  ];
  const r = L.planActivation("o1", "c1", "r1", doc(docs), urls, "TS", "t");
  assert.equal(r.ok, true);
  assert.equal(r.flipped, 7);
  assert.equal(r.update.status, "active");
  assert.equal(r.update.approvedRequestId, "r1");
  assert.equal(r.update.documents.length, 8);
  assert.deepEqual(r.update.documents[0],
    {documentKey: "personalPhoto", documentStatus: "approved", documentURL: "p0", reviewedBy: "TS", reviewedAt: "t"});
  assert.equal(r.update.documents[7].documentStatus, "rejected");
});

test("planActivation denies what the rules deny", () => {
  const urls = L.requestUrlMap(req());
  const ok = [pend("personalPhoto", "p0")];
  assert.equal(L.planActivation("o1", "c1", "r1", doc(ok, {status: "active"}), urls, "", "t").reason, "delegate_not_pending");
  assert.equal(L.planActivation("o1", "c1", "r1", doc(ok, {statusReason: "delete"}), urls, "", "t").reason,
    "delegate_marked_for_delete");
  assert.equal(L.planActivation("o1", "c1", "r1", doc(ok, {companyUID: "c2"}), urls, "", "t").reason,
    "delegate_out_of_scope");
  assert.equal(L.planActivation("o2", "c1", "r1", doc(ok), urls, "", "t").reason, "delegate_out_of_scope");
  assert.equal(L.planActivation("o1", "c1", "r1", doc(new Array(9).fill(pend("personalPhoto", "p0"))), urls, "", "t").reason,
    "too_many_documents");
  assert.equal(L.planActivation("o1", "c1", "r1", doc([pend("personalPhoto", "other")]), urls, "", "t").reason,
    "document_url_mismatch");
  assert.equal(L.planActivation("o1", "c1", "r1", doc([pend("nationalityId", "f0", {secondaryURL: "x"})]), urls, "", "t").reason,
    "document_url_mismatch");
  assert.equal(L.planActivation("o1", "c1", "r1", doc([pend("criminalRecord", "q")]), urls, "", "t").reason,
    "document_url_mismatch");
  assert.equal(L.planActivation("o1", "c1", "r1", doc([pend("#nidBack", "b0")]), urls, "", "t").reason,
    "document_url_mismatch");
  // Title-case 'Pending' status is accepted like the rules' techSignup.
  assert.equal(L.planActivation("o1", "c1", "r1", doc(ok, {status: "Pending"}), urls, "", "t").ok, true);
});

test("alreadyApplied only when request approved and every doc bound", () => {
  const act = {status: "active", approvedRequestId: "r1"};
  assert.equal(L.alreadyApplied("r1", req({status: "approved"}), [act, act]), true);
  assert.equal(L.alreadyApplied("r1", req(), [act]), false);
  assert.equal(L.alreadyApplied("r1", req({status: "approved"}), [act, null]), false);
  assert.equal(L.alreadyApplied("r1", req({status: "approved"}), [{status: "active", approvedRequestId: "r2"}]), false);
});
