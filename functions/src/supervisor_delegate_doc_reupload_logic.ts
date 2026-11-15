import {normalizeRoleKey} from "./staff_phone_lookup_logic";

const SUPERVISOR = new Set(["supervisor", "company_supervisor"]);

export function documentKeyForDocType(docType: string): string {
  if (docType === "nationalIdFront" || docType === "nationalIdBack") return "nationalityId";
  return docType;
}

export function mergeReuploadedDocument(
  raw: unknown,
  docType: string,
  newUrl: string,
  at: string,
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
  base.documentStatus = "pending";
  delete base.reviewedBy;
  delete base.reviewedAt;

  if (idx >= 0) docs[idx] = base;
  else docs.push(base);
  return docs;
}

export function urlFieldsForDocType(
  docType: string,
  newUrl: string,
): Record<string, string> {
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
  const targetOrg = String(target.organizationUID || "").trim();
  const targetCo = String(target.companyUID || "").trim();
  if (!callerOrg || !callerCo || callerOrg !== targetOrg || callerCo !== targetCo) {
    return {ok: false, reason: "out_of_scope"};
  }
  const st = String(target.status || "").trim().toLowerCase();
  if (st !== "active") return {ok: false, reason: "delegate_not_active"};
  if (caller.uid === target.delegateUid) return {ok: false, reason: "self"};
  return {ok: true};
}