import {normalizeRoleKey} from "./staff_phone_lookup_logic";

const SUPERVISOR = new Set(["supervisor", "company_supervisor"]);

/** Must match profile_screen doc types that supervisors may replace. */
export const SUPERVISOR_REUPLOAD_DOC_TYPES = new Set([
  "personalPhoto",
  "nationalIdFront",
  "nationalIdBack",
  "paymentReceipt",
]);

export function isKnownSupervisorReuploadDocType(docType: string): boolean {
  return SUPERVISOR_REUPLOAD_DOC_TYPES.has(docType);
}

export function documentKeyForDocType(docType: string): string {
  if (docType === "nationalIdFront" || docType === "nationalIdBack") return "nationalityId";
  return docType;
}

/**
 * TAS-331: sets the re-uploaded file on a documents[] entry. [newUrl] is the
 * legacy download URL ("" once write_legacy_storage_urls is off); [newPath]
 * the Storage object path, written as documentPath / secondaryPath. Without
 * a path the entry's previous path is removed, so a stale path never
 * outlives the file it pointed to (readers pick the path first).
 */
export function setEntryRef(
  base: Record<string, unknown>,
  docType: string,
  newUrl: string,
  newPath?: string,
): void {
  const path = String(newPath || "").trim();
  const set = (urlKey: string, pathKey: string) => {
    base[urlKey] = newUrl;
    if (path) base[pathKey] = path;
    else delete base[pathKey];
  };
  if (docType === "nationalIdFront") {
    set("documentURL", "documentPath");
    if (base.secondaryURL === undefined) base.secondaryURL = "";
  } else if (docType === "nationalIdBack") {
    set("secondaryURL", "secondaryPath");
    if (base.documentURL === undefined) base.documentURL = "";
  } else {
    set("documentURL", "documentPath");
  }
}

export function mergeReuploadedDocument(
  raw: unknown,
  docType: string,
  newUrl: string,
  at: string,
  newPath?: string,
): Record<string, unknown>[] {
  const key = documentKeyForDocType(docType);
  const docs: Record<string, unknown>[] = Array.isArray(raw)
    ? raw.filter((e): e is Record<string, unknown> => !!e && typeof e === "object")
    : [];
  const idx = docs.findIndex((d) => String(d.documentKey || "") === key);
  const base: Record<string, unknown> =
    idx >= 0 ? {...docs[idx]} : {documentKey: key};

  setEntryRef(base, docType, newUrl, newPath);
  base.uploadedAt = at;
  delete base.rejectionReason;
  base.documentStatus = "pending";
  delete base.reviewedBy;
  delete base.reviewedAt;

  if (idx >= 0) docs[idx] = base;
  else docs.push(base);
  return docs;
}

/**
 * TAS-331: top-level Storage path field for [docType]: the new path, or
 * null (= delete the field) when the caller sent only a URL, so an old
 * path never sits next to a newer URL.
 */
export function pathFieldsForDocType(
  docType: string,
  newPath: string,
): Record<string, string | null> {
  const v = String(newPath || "").trim() || null;
  switch (docType) {
    case "personalPhoto":
      return {profileImagePath: v};
    case "nationalIdFront":
      return {nationalIdFrontPath: v};
    case "nationalIdBack":
      return {nationalIdBackPath: v};
    case "paymentReceipt":
      return {receiptImagePath: v};
    default:
      return {};
  }
}

export function urlFieldsForDocType(
  docType: string,
  newUrl: string,
): Record<string, string> {
  if (!isKnownSupervisorReuploadDocType(docType)) return {};
  switch (docType) {
    case "personalPhoto":
      return {profileImageUrl: newUrl, personalPhotoURL: newUrl, photoURL: newUrl};
    case "nationalIdFront":
      return {nationalIdFrontUrl: newUrl};
    case "nationalIdBack":
      return {nationalIdBackUrl: newUrl};
    case "paymentReceipt":
      return {receiptImageUrl: newUrl};
    default:
      return {};
  }
}

export type SupervisorDocReuploadDecision =
  | {ok: true}
  | {ok: false; reason: string};

export function decideSupervisorDocReupload(
  caller: {
    role: unknown;
    organizationUID?: unknown;
    companyUID?: unknown;
    uid: string;
  },
  target: {
    delegateUid: string;
    organizationUID: string;
    companyUID: string;
    status: unknown;
  },
): SupervisorDocReuploadDecision {
  const role = normalizeRoleKey(caller.role);
  if (!SUPERVISOR.has(role)) return {ok: false, reason: "caller_not_supervisor"};
  const callerOrg = String(caller.organizationUID || "").trim();
  const callerCo = String(caller.companyUID || "").trim();
  // Target org/company come from the stored delegate doc (server), never the client.
  const delegateOrg = String(target.organizationUID || "").trim();
  const delegateCo = String(target.companyUID || "").trim();
  if (!callerOrg || !callerCo || !delegateOrg || !delegateCo) {
    return {ok: false, reason: "out_of_scope"};
  }
  if (callerOrg !== delegateOrg || callerCo !== delegateCo) {
    return {ok: false, reason: "out_of_scope"};
  }
  const st = String(target.status || "").trim().toLowerCase();
  if (st !== "active") return {ok: false, reason: "delegate_not_active"};
  if (caller.uid === target.delegateUid) return {ok: false, reason: "self"};
  return {ok: true};
}
/**
 * TAS-373 (user decision 2026-11-27, replaces the 2026-11-15 rule): a
 * supervisor replacing the delegate's ID card sends the delegate back to
 * review (`pending` + this reason); a new personal photo or payment receipt
 * keeps the delegate `active` (the document itself is still `pending`).
 */
export const SUPERVISOR_ID_REUPLOAD_REASON = "supervisor_id_reupload";

export function reuploadSetsDelegatePending(docType: string): boolean {
  return docType === "nationalIdFront" || docType === "nationalIdBack";
}

/**
 * After a privileged review of a document: the delegate goes back to
 * `active` when it is `pending` only because a supervisor replaced the ID
 * card and that ID document is now approved.
 */
export function idReviewRestoresActive(
  delegate: Record<string, unknown> | null | undefined,
  documentsAfterReview: unknown,
): boolean {
  const d = delegate || {};
  if (String(d.status || "").trim().toLowerCase() !== "pending") return false;
  if (String(d.statusReason || "") !== SUPERVISOR_ID_REUPLOAD_REASON) return false;
  const docs = Array.isArray(documentsAfterReview) ? documentsAfterReview : [];
  const id = docs.find((e) => e && typeof e === "object" &&
    String((e as Record<string, unknown>).documentKey || "") === "nationalityId") as
    Record<string, unknown> | undefined;
  return !!id && String(id.documentStatus || "").trim().toLowerCase() === "approved";
}
