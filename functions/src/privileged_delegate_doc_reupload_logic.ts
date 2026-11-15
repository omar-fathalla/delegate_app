import {isReviewerRole} from "./delegate_profile_edit_logic";
import {
  documentKeyForDocType,
  isKnownSupervisorReuploadDocType,
  urlFieldsForDocType,
} from "./supervisor_delegate_doc_reupload_logic";

export {isKnownSupervisorReuploadDocType, urlFieldsForDocType};

export function mergePrivilegedReuploadedDocument(
  raw: unknown,
  docType: string,
  newUrl: string,
  at: string,
  reviewerUid: string,
): Record<string, unknown>[] {
  const key = documentKeyForDocType(docType);
  const docs: Record<string, unknown>[] = Array.isArray(raw)
    ? raw.filter((e): e is Record<string, unknown> => !!e && typeof e === "object")
    : [];
  const idx = docs.findIndex((d) => String(d.documentKey || "") === key);
  const base: Record<string, unknown> =
    idx >= 0 ? {...docs[idx]} : {documentKey: key};

  if (docType === "nationalIdFront") {
    base.documentURL = newUrl;
    if (base.secondaryURL === undefined) base.secondaryURL = "";
  } else if (docType === "nationalIdBack") {
    base.secondaryURL = newUrl;
    if (base.documentURL === undefined) base.documentURL = "";
  } else {
    base.documentURL = newUrl;
  }
  base.uploadedAt = at;
  delete base.rejectionReason;
  base.documentStatus = "approved";
  base.reviewedBy = reviewerUid;
  base.reviewedAt = at;

  if (idx >= 0) docs[idx] = base;
  else docs.push(base);
  return docs;
}

export type PrivilegedDocReuploadDecision =
  | {ok: true}
  | {ok: false; reason: string};

export function decidePrivilegedDocReupload(
  caller: {role: unknown; uid: string},
  target: {
    delegateUid: string;
    organizationUID: string;
    companyUID: string;
    status: unknown;
  },
  payload: {organizationUID: string; companyUID: string},
): PrivilegedDocReuploadDecision {
  if (!isReviewerRole(caller.role)) {
    return {ok: false, reason: "caller_not_privileged_staff"};
  }
  if (caller.uid === target.delegateUid) return {ok: false, reason: "self"};
  const wantOrg = String(payload.organizationUID || "").trim();
  const wantCo = String(payload.companyUID || "").trim();
  const delegateOrg = String(target.organizationUID || "").trim();
  const delegateCo = String(target.companyUID || "").trim();
  if (!wantOrg || !wantCo || !delegateOrg || !delegateCo) {
    return {ok: false, reason: "out_of_scope"};
  }
  if (wantOrg !== delegateOrg || wantCo !== delegateCo) {
    return {ok: false, reason: "out_of_scope"};
  }
  const st = String(target.status || "").trim().toLowerCase();
  if (st === "delete" || st === "deleted" || st === "disabled") {
    return {ok: false, reason: "delegate_not_editable"};
  }
  return {ok: true};
}