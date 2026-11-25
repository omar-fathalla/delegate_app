/**
 * TAS-336: pure checks for approveDelegateDocuments.
 *
 * The callable does, in one transaction, what the technical-support
 * request-approval batch did from the app: delegate_requests/{rid} goes
 * from 'pending' to 'approved' and every bound delegate doc that is still
 * 'pending' is activated with a status-only write (each 'pending' document
 * entry flips to 'approved'). The rules priced every flip at about 35
 * expressions, so 5+ flips on one doc hit the 1000-expression limit.
 *
 * Every check below mirrors firestore.rules (no new permission):
 * - request: requestTechReviewOk / techRequestReviewOk,
 *   newDelegateApprovalPaymentOk, requestApprovalOrgCheckOk;
 * - delegate doc: staffDocsApproveOk techSignup branch, techFlipOk,
 *   flipAt / reqUrlMap, techReqOk.
 * The caller's role comes from the ID-token custom claims, never from
 * users/{uid}.role (TAS-23).
 */

export type ApproverRole = "super_admin" | "tech_support";

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Letters only, lower case ("Super_Admin " -> "superadmin"), like normRoleStr. */
function roleKey(v: unknown): string {
  return typeof v === "string" ? v.toLowerCase().replace(/[^a-z]/g, "") : "";
}

/** Approver role from token claims only. Anything else returns null. */
export function approverRoleFromClaims(token: unknown): ApproverRole | null {
  const t = (token && typeof token === "object" ? token : {}) as Record<string, unknown>;
  const k = roleKey(t.role);
  if (k === "superadmin") return "super_admin";
  if (k === "technicalsupport" || k === "techsupport") return "tech_support";
  return null;
}

export const MAX_TARGETS = 20;
/** techFlipOk: n.size() <= 8. */
export const MAX_DOCUMENTS = 8;

export interface ApprovalInput {
  requestId: string;
  organizationUIDs: string[];
  reviewerName: string;
}

export type InputResult = {ok: true; value: ApprovalInput} | {ok: false; reason: string};

export function parseInput(data: unknown): InputResult {
  const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
  const requestId = str(p.requestId);
  if (!requestId || requestId.includes("/")) return {ok: false, reason: "invalid_request_id"};
  const raw = p.organizationUIDs;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_TARGETS) {
    return {ok: false, reason: "invalid_targets"};
  }
  const orgs: string[] = [];
  for (const o of raw) {
    const id = str(o);
    if (!id || id.includes("/")) return {ok: false, reason: "invalid_targets"};
    if (!orgs.includes(id)) orgs.push(id);
  }
  const reviewerName = str(p.reviewerName).slice(0, 120);
  return {ok: true, value: {requestId, organizationUIDs: orgs, reviewerName}};
}

export type Decision = {ok: true} | {ok: false; reason: string};

/** Delegate doc id bound to the request (techReqOk). */
export function boundDelegateId(requestId: string, req: Record<string, unknown>): string {
  const ty = str(req.requestType) || "new_delegate";
  return ty === "add_organization" ? str(req.existingDelegateUid) : requestId;
}

/**
 * Request-level checks for a 'pending' request (techRequestReviewOk,
 * newDelegateApprovalPaymentOk, requestApprovalOrgCheckOk).
 */
export function checkRequest(
  role: ApproverRole,
  callerUid: string,
  requestId: string,
  req: Record<string, unknown>,
): Decision {
  const ty = str(req.requestType) || "new_delegate";
  if (ty !== "new_delegate" && ty !== "add_organization") return {ok: false, reason: "unsupported_request_type"};
  if (str(req.actionType) === "update_national_id") return {ok: false, reason: "unsupported_request_type"};
  if (req.status !== "pending") return {ok: false, reason: "request_not_pending"};
  if (role === "tech_support"
    && (str(req.supervisorUid) === callerUid || str(req.createdBy) === callerUid)) {
    return {ok: false, reason: "own_request"};
  }
  // A delegate never approves itself (staffDocsApproveOk: auth.uid != delegateId).
  if (boundDelegateId(requestId, req) === callerUid) return {ok: false, reason: "own_request"};
  const method = str(req.paymentMethod);
  const pay = str(req.paymentStatus);
  if (ty === "new_delegate" && method === "paymob"
    && !["paid", "waived", "not_required"].includes(pay)) {
    return {ok: false, reason: "payment_not_settled"};
  }
  if (req.orgCompanyCheck !== "ok") return {ok: false, reason: "org_company_check_not_ok"};
  if (!boundDelegateId(requestId, req)) return {ok: false, reason: "no_bound_delegate"};
  if (!str(req.companyUID)) return {ok: false, reason: "no_company"};
  return {ok: true};
}

/**
 * techReqOk org binding: the request's organizationUID, or for new_delegate
 * the supervisor's own organization or one of the request's organizationUIDs.
 */
export function orgAllowed(orgId: string, req: Record<string, unknown>, supervisorOrg: string): boolean {
  const ty = str(req.requestType) || "new_delegate";
  if (orgId === str(req.organizationUID)) return true;
  if (ty !== "new_delegate") return false;
  const list = Array.isArray(req.organizationUIDs) ? req.organizationUIDs : [];
  return (supervisorOrg !== "" && orgId === supervisorOrg) || list.includes(orgId);
}

/** reqUrlMap: request URL per document key ('#nidBack' = national ID back). */
export function requestUrlMap(req: Record<string, unknown>): Record<string, string> {
  const s = (k: string) => (typeof req[k] === "string" ? req[k] as string : "");
  return {
    "personalPhoto": s("profileImageUrl"),
    "nationalityId": s("nationalIdFrontUrl"),
    "#nidBack": s("nationalIdBackUrl"),
    "paymentReceipt": s("receiptImageUrl"),
    "electronicPaymentReceipt": s("receiptImageUrl"),
    "electronic_payment_receipt": s("receiptImageUrl"),
    // TAS-331: '<key>#p' = the request's Storage path for that key
    // (documentPath; '#nidBack#p' = the ID back's secondaryPath). '' on a
    // request written before TAS-331.
    "personalPhoto#p": s("profileImagePath"),
    "nationalityId#p": s("nationalIdFrontPath"),
    "#nidBack#p": s("nationalIdBackPath"),
    "paymentReceipt#p": s("receiptImagePath"),
    "electronicPaymentReceipt#p": s("receiptImagePath"),
    "electronic_payment_receipt#p": s("receiptImagePath"),
  };
}

/**
 * TAS-331 (flipAt / entryOk): an entry's stored path, when it has one, must
 * be the request's path for that key. An entry without the field (older
 * app) passes.
 */
function pathMatches(entry: Record<string, unknown>, field: string, expected: string | undefined): boolean {
  if (!Object.prototype.hasOwnProperty.call(entry, field)) return true;
  return entry[field] === (expected ?? "");
}

export interface Activation {
  status: "active";
  reviewedBy: string;
  reviewedAt: string;
  approvedRequestId: string;
  documents?: unknown[];
}

export type ActivationResult =
  | {ok: true; update: Activation; flipped: number}
  | {ok: false; reason: string; documentKey?: string};

/**
 * One bound delegate doc: status 'pending' -> 'active' and every 'pending'
 * entry -> 'approved' with only documentStatus / reviewedBy / reviewedAt
 * changed. Same as the app's buildStatusOnlyActivation, plus the rules'
 * checks (techSignup, techFlipOk, flipAt, techReqOk path binding).
 */
export function planActivation(
  orgId: string,
  companyUID: string,
  requestId: string,
  doc: Record<string, unknown>,
  urls: Record<string, string>,
  reviewerName: string,
  reviewedAtIso: string,
): ActivationResult {
  if (doc.status !== "pending" && doc.status !== "Pending") return {ok: false, reason: "delegate_not_pending"};
  if (doc.statusReason === "delete") return {ok: false, reason: "delegate_marked_for_delete"};
  if (doc.companyUID !== companyUID || doc.organizationUID !== orgId) {
    return {ok: false, reason: "delegate_out_of_scope"};
  }
  const update: Activation = {
    status: "active",
    reviewedBy: reviewerName,
    reviewedAt: reviewedAtIso,
    approvedRequestId: requestId,
  };
  const raw = doc.documents;
  if (raw === undefined || raw === null) return {ok: true, update, flipped: 0};
  if (!Array.isArray(raw) || raw.length > MAX_DOCUMENTS) return {ok: false, reason: "too_many_documents"};
  let flipped = 0;
  const out: unknown[] = [];
  for (const e of raw) {
    if (!e || typeof e !== "object" || (e as Record<string, unknown>).documentStatus !== "pending") {
      out.push(e);
      continue;
    }
    const entry = e as Record<string, unknown>;
    const key = typeof entry.documentKey === "string" ? entry.documentKey : "";
    const url = typeof entry.documentURL === "string" ? entry.documentURL : "";
    const expected = Object.prototype.hasOwnProperty.call(urls, key) && !key.includes("#") ? urls[key] : null;
    if (expected === null || expected !== url) {
      return {ok: false, reason: "document_url_mismatch", documentKey: key};
    }
    if (!pathMatches(entry, "documentPath", urls[key + "#p"])) {
      return {ok: false, reason: "document_url_mismatch", documentKey: key};
    }
    if (key === "nationalityId") {
      const back = typeof entry.secondaryURL === "string" ? entry.secondaryURL : "";
      if (back !== urls["#nidBack"]) return {ok: false, reason: "document_url_mismatch", documentKey: key};
      if (!pathMatches(entry, "secondaryPath", urls["#nidBack#p"])) {
        return {ok: false, reason: "document_url_mismatch", documentKey: key};
      }
    }
    out.push({...entry, documentStatus: "approved", reviewedBy: reviewerName, reviewedAt: reviewedAtIso});
    flipped++;
  }
  update.documents = out;
  return {ok: true, update, flipped};
}

/** Replay: the request is approved and every target already carries the binding. */
export function alreadyApplied(
  requestId: string,
  req: Record<string, unknown>,
  docs: Array<Record<string, unknown> | null>,
): boolean {
  if (req.status !== "approved") return false;
  return docs.every((d) => d !== null
    && d.approvedRequestId === requestId
    && typeof d.status === "string" && d.status.toLowerCase() === "active");
}

/** Arabic message per reason (shown in the app). */
export function reasonMessage(reason: string): string {
  switch (reason) {
    case "not_approver": return "ليس لديك صلاحية اعتماد طلبات المناديب.";
    case "own_request": return "لا يمكنك اعتماد طلب قمت بإنشائه.";
    case "request_not_found": return "لم يتم العثور على الطلب.";
    case "request_not_pending": return "الطلب لم يعد قيد المراجعة.";
    case "unsupported_request_type": return "نوع الطلب لا يُعتمد بهذه الطريقة.";
    case "payment_not_settled": return "لا يمكن اعتماد المندوب قبل تأكيد دفع الاشتراك إلكترونياً (Paymob).";
    case "org_company_check_not_ok": return "السلسلة المطلوبة غير متاحة لهذه الشركة حالياً.";
    case "org_not_in_request": return "إحدى السلاسل ليست ضمن هذا الطلب.";
    case "delegate_not_found": return "لم يتم العثور على سجل المندوب المعلق في إحدى السلاسل.";
    case "delegate_not_pending": return "سجل المندوب في إحدى السلاسل ليس قيد المراجعة.";
    case "delegate_marked_for_delete": return "سجل المندوب عليه طلب حذف.";
    case "delegate_out_of_scope": return "سجل المندوب لا يخص شركة أو سلسلة هذا الطلب.";
    case "too_many_documents": return "عدد مستندات المندوب أكبر من المسموح.";
    case "document_url_mismatch": return "أحد المستندات قيد المراجعة لا يطابق ملفات الطلب.";
    default: return "تعذر اعتماد الطلب.";
  }
}
