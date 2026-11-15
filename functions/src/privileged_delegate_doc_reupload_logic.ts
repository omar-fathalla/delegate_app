import {isReviewerRole} from "./delegate_profile_edit_logic";
import {
  documentKeyForDocType,
  isKnownSupervisorReuploadDocType,
  urlFieldsForDocType,
} from "./supervisor_delegate_doc_reupload_logic";

export {isKnownSupervisorReuploadDocType, urlFieldsForDocType};

export type DelegateDocStorageResolve =
  | {ok: true; objectPath: string}
  | {ok: false; reason: string};

const MAX_PATH_DECODES = 8;

/** Repeated decodeURIComponent (double-encoding safe). */
export function decodeStorageObjectPathFully(encoded: string): string {
  let s = String(encoded || "");
  for (let i = 0; i < MAX_PATH_DECODES; i++) {
    try {
      const next = decodeURIComponent(s);
      if (next === s) break;
      s = next;
    } catch {
      break;
    }
  }
  return s;
}

/**
 * Reject traversal, empty segments, backslashes, NUL; require exact
 * delegate_documents/{delegateUid}/ prefix on the fully decoded path.
 */
export function validateDelegateDocumentObjectPath(
  objectPath: string,
  delegateUid: string,
): DelegateDocStorageResolve {
  const uid = String(delegateUid || "").trim();
  const path = String(objectPath || "");
  if (!uid || !path) return {ok: false, reason: "missing_url"};
  if (path.includes("\0") || path.includes("\\")) {
    return {ok: false, reason: "path_traversal"};
  }
  if (path.includes("..")) return {ok: false, reason: "path_traversal"};
  const segments = path.split("/");
  for (const seg of segments) {
    if (seg === "" || seg === "." || seg === "..") {
      return {ok: false, reason: "path_traversal"};
    }
  }
  const prefix = `delegate_documents/${uid}/`;
  if (!path.startsWith(prefix) || path.length <= prefix.length) {
    return {ok: false, reason: "wrong_delegate_folder"};
  }
  return {ok: true, objectPath: path};
}

function bucketMatchesDefault(urlBucket: string, defaultBucket: string): boolean {
  const want = String(defaultBucket || "").trim().toLowerCase();
  const got = String(urlBucket || "").trim().toLowerCase();
  return want !== "" && got === want;
}

function isHttpsStorageHost(host: string): boolean {
  return host === "firebasestorage.googleapis.com" || host === "storage.googleapis.com";
}

/** Resolve download URL or gs path; bucket must be [defaultBucket] when present in URL. */
export function resolveDelegateDocumentStorageObject(
  newUrl: string,
  delegateUid: string,
  defaultBucket: string,
): DelegateDocStorageResolve {
  const v = String(newUrl || "").trim();
  const defBucket = String(defaultBucket || "").trim();
  if (!v || !defBucket) return {ok: false, reason: "missing_url"};
  if (/^(javascript|data|vbscript|http):/i.test(v)) {
    return {ok: false, reason: "invalid_image_url"};
  }

  if (v.startsWith("gs://")) {
    const rest = v.slice("gs://".length);
    const slash = rest.indexOf("/");
    if (slash < 1) return {ok: false, reason: "invalid_storage_url"};
    const gsBucket = rest.slice(0, slash);
    if (!bucketMatchesDefault(gsBucket, defBucket)) {
      return {ok: false, reason: "wrong_bucket"};
    }
    const decoded = decodeStorageObjectPathFully(rest.slice(slash + 1));
    return validateDelegateDocumentObjectPath(decoded, delegateUid);
  }

  if (v.startsWith("delegate_documents/")) {
    const decoded = decodeStorageObjectPathFully(v);
    return validateDelegateDocumentObjectPath(decoded, delegateUid);
  }

  try {
    const u = new URL(v);
    if (u.protocol !== "https:") return {ok: false, reason: "invalid_image_url"};
    const host = u.hostname.toLowerCase();
    if (!isHttpsStorageHost(host)) {
      return {ok: false, reason: "invalid_image_url"};
    }
    let encodedPath = "";
    let urlBucket = "";
    if (host === "firebasestorage.googleapis.com") {
      const bm = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
      if (!bm) return {ok: false, reason: "invalid_storage_url"};
      urlBucket = decodeURIComponent(bm[1]);
      encodedPath = bm[2];
    } else {
      const parts = u.pathname.split("/").filter(Boolean);
      if (parts.length < 2) return {ok: false, reason: "invalid_storage_url"};
      urlBucket = decodeURIComponent(parts[0]);
      encodedPath = parts.slice(1).join("/");
    }
    if (!bucketMatchesDefault(urlBucket, defBucket)) {
      return {ok: false, reason: "wrong_bucket"};
    }
    const decoded = decodeStorageObjectPathFully(encodedPath);
    return validateDelegateDocumentObjectPath(decoded, delegateUid);
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

export type PrivilegedReviewResult =
  | {ok: true; documents: Record<string, unknown>[]}
  | {ok: false; reason: "not_found" | "not_pending" | "already_approved"};

function normalizeDocStatus(status: unknown): string {
  return String(status || "").trim().toLowerCase();
}

export function applyPrivilegedDocumentReview(
  raw: unknown,
  docType: string,
  approve: boolean,
  reviewerUid: string,
  rejectionReason: string | undefined,
  at: string,
): PrivilegedReviewResult {
  const key = documentKeyForDocType(docType);
  const docs: Record<string, unknown>[] = Array.isArray(raw)
    ? raw.filter((e): e is Record<string, unknown> => !!e && typeof e === "object")
    : [];
  const idx = docs.findIndex((d) => String(d.documentKey || "") === key);
  if (idx < 0) return {ok: false, reason: "not_found"};
  const e: Record<string, unknown> = {...docs[idx]};
  const st = normalizeDocStatus(e.documentStatus);
  if (st === "approved" && approve) {
    return {ok: false, reason: "already_approved"};
  }
  if (st !== "pending") {
    return {ok: false, reason: st === "approved" ? "already_approved" : "not_pending"};
  }
  e.documentStatus = approve ? "approved" : "rejected";
  e.reviewedBy = reviewerUid;
  e.reviewedAt = at;
  if (approve) {
    delete e.rejectionReason;
  } else {
    e.rejectionReason = String(rejectionReason || "").trim();
  }
  docs[idx] = e;
  return {ok: true, documents: docs};
}