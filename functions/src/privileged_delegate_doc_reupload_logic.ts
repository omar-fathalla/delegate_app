import {isAllowedImageUrl, isReviewerRole} from "./delegate_profile_edit_logic";
import {
  documentKeyForDocType,
  isKnownSupervisorReuploadDocType,
  urlFieldsForDocType,
} from "./supervisor_delegate_doc_reupload_logic";

export {isKnownSupervisorReuploadDocType, urlFieldsForDocType};

export type DelegateDocStorageResolve =
  | {ok: true; objectPath: string; bucket?: string}
  | {ok: false; reason: string};

/** Resolve a download URL or gs path to delegate_documents/{delegateUid}/... */
export function resolveDelegateDocumentStorageObject(
  newUrl: string,
  delegateUid: string,
): DelegateDocStorageResolve {
  const v = String(newUrl || "").trim();
  const uid = String(delegateUid || "").trim();
  if (!v || !uid) return {ok: false, reason: "missing_url"};
  if (!isAllowedImageUrl(v, uid)) return {ok: false, reason: "invalid_image_url"};
  if (v.startsWith("delegate_documents/")) {
    return {ok: true, objectPath: v};
  }
  try {
    const u = new URL(v);
    const host = u.hostname.toLowerCase();
    if (host === "firebasestorage.googleapis.com") {
      const bm = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
      if (!bm) return {ok: false, reason: "invalid_storage_url"};
      const objectPath = decodeURIComponent(bm[2]);
      if (!objectPath.startsWith(`delegate_documents/${uid}/`)) {
        return {ok: false, reason: "wrong_delegate_folder"};
      }
      return {ok: true, objectPath, bucket: decodeURIComponent(bm[1])};
    }
    if (host === "storage.googleapis.com") {
      const parts = u.pathname.split("/").filter(Boolean);
      if (parts.length < 2) return {ok: false, reason: "invalid_storage_url"};
      const objectPath = parts.slice(1).join("/");
      if (!objectPath.startsWith(`delegate_documents/${uid}/`)) {
        return {ok: false, reason: "wrong_delegate_folder"};
      }
      return {ok: true, objectPath, bucket: decodeURIComponent(parts[0])};
    }
    const objectPath = u.pathname.replace(/^\//, "");
    if (objectPath.startsWith(`delegate_documents/${uid}/`)) {
      return {ok: true, objectPath, bucket: host};
    }
    return {ok: false, reason: "wrong_delegate_folder"};
  } catch {
    return {ok: false, reason: "invalid_storage_url"};
  }
}

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

export function applyPrivilegedDocumentReview(
  raw: unknown,
  docType: string,
  approve: boolean,
  reviewerUid: string,
  rejectionReason: string | undefined,
  at: string,
): Record<string, unknown>[] | null {
  const key = documentKeyForDocType(docType);
  const docs: Record<string, unknown>[] = Array.isArray(raw)
    ? raw.filter((e): e is Record<string, unknown> => !!e && typeof e === "object")
    : [];
  const idx = docs.findIndex((d) => String(d.documentKey || "") === key);
  if (idx < 0) return null;
  const e: Record<string, unknown> = {...docs[idx]};
  e.documentStatus = approve ? "approved" : "rejected";
  e.reviewedBy = reviewerUid;
  e.reviewedAt = at;
  if (approve) {
    delete e.rejectionReason;
  } else {
    e.rejectionReason = String(rejectionReason || "").trim();
  }
  docs[idx] = e;
  return docs;
}