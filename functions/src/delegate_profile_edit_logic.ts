/** Supervisor profile edits and national-ID update requests. Pure helpers. */

export const EDITOR_ROLES = new Set([
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
]);

export const REVIEWER_ROLES = new Set([
  "super-admin", "super_admin", "superadmin", "superAdmin",
  "Super-Admin", "SUPER_ADMIN",
  "technical_support", "technical-support", "technicalSupport",
  "technicalsupport", "tech_support", "techsupport",
]);

export const EDITABLE_REQUEST_STATUSES = new Set([
  "pending", "action_required",
]);

export const EDITABLE_DELEGATE_STATUSES = new Set([
  "active", "approved", "pending", "action_required",
]);

export const PROFILE_FIELD_KEYS = [
  "fullName",
  "firstName",
  "secondName",
  "thirdName",
  "middleName",
  "lastName",
  "phoneNumber",
  "phone",
  "profileImageUrl",
  "personalPhotoURL",
  "personalPhotoUrl",
  "photoURL",
  "nationalIdFrontUrl",
  "nationalIdBackUrl",
  "documents",
  "updatedAt",
] as const;

export const ALERT_FIELDS = new Set([
  "fullName",
  "nationalIdFrontUrl",
  "nationalIdBackUrl",
]);

export type ProfileEditField =
  | "fullName"
  | "phoneNumber"
  | "personalPhotoURL"
  | "nationalIdFrontUrl"
  | "nationalIdBackUrl";

export interface ProfileEditInput {
  fullName?: string;
  phoneNumber?: string;
  personalPhotoURL?: string;
  nationalIdFrontUrl?: string;
  nationalIdBackUrl?: string;
}

export function canonicalizeRole(role: unknown): string {
  return String(role || "").trim().toLowerCase().replace(/_/g, "-");
}

export function isEditorRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  return EDITOR_ROLES.has(raw) || EDITOR_ROLES.has(canonicalizeRole(role));
}

export function isReviewerRole(role: unknown): boolean {
  const raw = String(role || "").trim();
  return REVIEWER_ROLES.has(raw) || REVIEWER_ROLES.has(canonicalizeRole(role));
}

export function isEditableRequestStatus(status: unknown): boolean {
  return EDITABLE_REQUEST_STATUSES.has(String(status || "").toLowerCase());
}

export function isEditableDelegateStatus(status: unknown): boolean {
  return EDITABLE_DELEGATE_STATUSES.has(String(status || "").toLowerCase());
}

export function splitFullName(fullName: string): {
  firstName: string;
  secondName: string;
  thirdName: string;
  middleName: string;
  lastName: string;
} {
  const parts = fullName.trim().split(/\s+/).filter(Boolean);
  const firstName = parts[0] || "";
  const lastName = parts.length > 1 ? parts[parts.length - 1] : "";
  const middle = parts.slice(1, Math.max(parts.length - 1, 1));
  const secondName = middle[0] || "";
  const thirdName = middle.slice(1).join(" ");
  return {
    firstName,
    secondName,
    thirdName,
    middleName: middle.join(" "),
    lastName,
  };
}

export function sanitizeProfileEdit(raw: ProfileEditInput): {
  fields: ProfileEditInput;
  keys: ProfileEditField[];
} {
  const fields: ProfileEditInput = {};
  const keys: ProfileEditField[] = [];
  const take = (key: ProfileEditField, value: unknown) => {
    if (typeof value !== "string") return;
    const v = value.trim();
    if (!v) return;
    fields[key] = v;
    keys.push(key);
  };
  take("fullName", raw.fullName);
  take("phoneNumber", raw.phoneNumber);
  take("personalPhotoURL", raw.personalPhotoURL);
  take("nationalIdFrontUrl", raw.nationalIdFrontUrl);
  take("nationalIdBackUrl", raw.nationalIdBackUrl);
  return {fields, keys};
}

export function shouldAlertAdmins(keys: ProfileEditField[]): boolean {
  return keys.some((k) => ALERT_FIELDS.has(k));
}

export function fieldArabicLabel(field: string): string {
  switch (field) {
  case "fullName": return "الاسم";
  case "phoneNumber": return "رقم الموبايل";
  case "personalPhotoURL": return "الصورة الشخصية";
  case "nationalIdFrontUrl": return "صورة البطاقة الأمامية";
  case "nationalIdBackUrl": return "صورة البطاقة الخلفية";
  case "nationalId":
  case "nationalityID": return "الرقم القومي";
  default: return field;
  }
}

export function isImageField(field: string): boolean {
  return field === "personalPhotoURL"
    || field === "nationalIdFrontUrl"
    || field === "nationalIdBackUrl";
}

export interface AuditRecordDraft {
  actorUid: string;
  actorName: string;
  actorRole: string;
  field: string;
  oldValue: string;
  newValue: string;
  delegateUid: string;
  delegateName: string;
  companyUID: string;
  companyName: string;
  organizationUID: string;
  source: "direct_edit" | "national_id_approval" | "national_id_rejection";
  requestId?: string;
}

export function auditDoc(draft: AuditRecordDraft): Record<string, unknown> {
  return {
    actorUid: draft.actorUid,
    actorName: draft.actorName,
    actorRole: draft.actorRole,
    field: draft.field,
    fieldLabel: fieldArabicLabel(draft.field),
    oldValue: draft.oldValue,
    newValue: draft.newValue,
    isImage: isImageField(draft.field),
    delegateUid: draft.delegateUid,
    delegateName: draft.delegateName,
    companyUID: draft.companyUID,
    companyName: draft.companyName,
    organizationUID: draft.organizationUID,
    source: draft.source,
    ...(draft.requestId ? {requestId: draft.requestId} : {}),
  };
}

/** Merge personal-photo / national-ID document entries with new URLs. */
export function patchDocuments(
  existing: unknown,
  fields: ProfileEditInput,
): unknown[] | undefined {
  const photo = fields.personalPhotoURL;
  const front = fields.nationalIdFrontUrl;
  const back = fields.nationalIdBackUrl;
  if (!photo && !front && !back) return undefined;
  const list = Array.isArray(existing) ? existing.map((e) => ({...(e as Record<string, unknown>)})) : [];
  const upsert = (key: string, patch: Record<string, unknown>) => {
    const idx = list.findIndex((e) => String(e.documentKey || e.key || "") === key);
    if (idx >= 0) {
      list[idx] = {...list[idx], ...patch};
    } else {
      list.push({documentKey: key, documentStatus: "approved", ...patch});
    }
  };
  if (photo) {
    upsert("personalPhoto", {documentURL: photo, documentStatus: "approved"});
  }
  if (front || back) {
    const prev = list.find((e) => String(e.documentKey || "") === "nationalityId") || {};
    upsert("nationalityId", {
      documentURL: front || prev.documentURL || "",
      secondaryURL: back || prev.secondaryURL || "",
      documentStatus: "approved",
    });
  }
  return list;
}

export function applyProfileFields(
  current: Record<string, unknown>,
  fields: ProfileEditInput,
): Record<string, unknown> {
  const patch: Record<string, unknown> = {};
  if (fields.fullName) {
    const parts = splitFullName(fields.fullName);
    patch.fullName = fields.fullName;
    patch.firstName = parts.firstName;
    patch.secondName = parts.secondName;
    patch.thirdName = parts.thirdName;
    patch.middleName = parts.middleName;
    patch.lastName = parts.lastName;
  }
  if (fields.phoneNumber) {
    patch.phoneNumber = fields.phoneNumber;
    if (Object.prototype.hasOwnProperty.call(current, "phone")) {
      patch.phone = fields.phoneNumber;
    }
  }
  if (fields.personalPhotoURL) {
    patch.profileImageUrl = fields.personalPhotoURL;
    patch.personalPhotoURL = fields.personalPhotoURL;
    if (Object.prototype.hasOwnProperty.call(current, "personalPhotoUrl")
      || Object.prototype.hasOwnProperty.call(current, "photoURL")) {
      if (Object.prototype.hasOwnProperty.call(current, "personalPhotoUrl")) {
        patch.personalPhotoUrl = fields.personalPhotoURL;
      }
      if (Object.prototype.hasOwnProperty.call(current, "photoURL")) {
        patch.photoURL = fields.personalPhotoURL;
      }
    } else {
      patch.personalPhotoUrl = fields.personalPhotoURL;
      patch.photoURL = fields.personalPhotoURL;
    }
  }
  if (fields.nationalIdFrontUrl) patch.nationalIdFrontUrl = fields.nationalIdFrontUrl;
  if (fields.nationalIdBackUrl) patch.nationalIdBackUrl = fields.nationalIdBackUrl;
  const docs = patchDocuments(current.documents, fields);
  if (docs) patch.documents = docs;
  return patch;
}

export function valueOf(data: Record<string, unknown>, field: ProfileEditField | "nationalId"): string {
  if (field === "personalPhotoURL") {
    return String(data.personalPhotoURL || data.personalPhotoUrl || data.profileImageUrl || data.photoURL || "");
  }
  if (field === "nationalId") {
    return String(data.nationalId || data.nationalityID || "");
  }
  return String(data[field] || "");
}

export type CompanyScopeResult = "ok" | "missing-company" | "mismatch";

/** Editors must have a companyUID and it must match the target company. */
export function companyScopeDecision(
  callerCompanyUID: string,
  targetCompanyUID: string,
): CompanyScopeResult {
  if (!String(callerCompanyUID || "").trim()) return "missing-company";
  if (String(callerCompanyUID).trim() !== String(targetCompanyUID || "").trim()) {
    return "mismatch";
  }
  return "ok";
}

/**
 * Never patch a legacy no-companyUID record, or a doc sitting under
 * another company's organizations/{o}/companies/{other}/ path.
 */
export function isPatchableTarget(
  companyUID: string,
  data: {companyUID?: unknown; companyId?: unknown},
  path: string,
): boolean {
  const co = String(data.companyUID || data.companyId || "").trim();
  if (!co || co !== companyUID) return false;
  const parts = path.split("/").filter(Boolean);
  const idx = parts.indexOf("companies");
  if (idx >= 0 && parts.length > idx + 1) {
    const pathCompany = parts[idx + 1];
    if (pathCompany && pathCompany !== companyUID) return false;
  }
  return true;
}

const STORAGE_HOSTS = new Set([
  "firebasestorage.googleapis.com",
  "storage.googleapis.com",
]);

/** https Firebase Storage URLs, or delegate_documents/{uid}/... paths. */
export function isAllowedImageUrl(url: string, delegateUid?: string): boolean {
  const v = String(url || "").trim();
  if (!v) return false;
  if (/^(javascript|data|vbscript|http):/i.test(v)) return false;
  if (v.startsWith("delegate_documents/")) {
    if (v.includes("..") || v.includes("//")) return false;
    if (delegateUid) {
      return v.startsWith(`delegate_documents/${delegateUid}/`)
        && v.slice(`delegate_documents/${delegateUid}/`.length).length > 0;
    }
    return /^delegate_documents\/[^/]+\/[^/]+/.test(v);
  }
  try {
    const u = new URL(v);
    if (u.protocol !== "https:") return false;
    const host = u.hostname.toLowerCase();
    if (STORAGE_HOSTS.has(host)) return true;
    if (host === "firebasestorage.app" || host.endsWith(".firebasestorage.app")) return true;
    if (host.endsWith(".appspot.com")) return true;
    return false;
  } catch {
    return false;
  }
}

export function assertImageFields(fields: ProfileEditInput, delegateUid?: string): void {
  const keys: Array<keyof ProfileEditInput> = [
    "personalPhotoURL", "nationalIdFrontUrl", "nationalIdBackUrl",
  ];
  for (const key of keys) {
    const value = fields[key];
    if (value && !isAllowedImageUrl(value, delegateUid)) {
      throw new Error("invalid-image-url");
    }
  }
}

export const PRIVILEGED_ALERT_TYPES = [
  "delegate_profile_edit",
  "delegate_national_id_request",
] as const;

/** One alert payload per recipient. No phone numbers. */
export function privilegedAlertDoc(opts: {
  recipientUid: string;
  title: string;
  body: string;
  type: string;
  senderName: string;
  senderRole: string;
  companyUID: string;
  organizationUID: string;
  requestId?: string;
  targetDelegateUid?: string;
}): Record<string, unknown> {
  return {
    delegateUid: opts.recipientUid,
    title: opts.title,
    body: opts.body,
    type: opts.type,
    senderName: opts.senderName,
    senderRole: opts.senderRole,
    companyUID: opts.companyUID,
    organizationId: opts.organizationUID,
    isRead: false,
    targetRoles: ["superAdmin", "technicalSupport"],
    ...(opts.requestId ? {requestId: opts.requestId} : {}),
    ...(opts.targetDelegateUid ? {targetDelegateUid: opts.targetDelegateUid} : {}),
  };
}

export function uniqueRecipientIds(ids: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of ids) {
    const v = String(id || "").trim();
    if (!v || seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}

export function supervisorReviewAlertDoc(opts: {
  supervisorUid: string;
  approved: boolean;
  reviewerName: string;
  delegateName: string;
  companyUID: string;
  organizationUID: string;
  requestId: string;
  targetDelegateUid: string;
  rejectionReason?: string;
}): Record<string, unknown> {
  const approved = opts.approved;
  const who = opts.delegateName || opts.targetDelegateUid;
  const reason = (opts.rejectionReason || "").trim();
  return {
    delegateUid: opts.supervisorUid,
    title: approved ? "تم اعتماد طلب تعديل الرقم القومي" : "تم رفض طلب تعديل الرقم القومي",
    body: approved
      ? `تم اعتماد طلب تعديل الرقم القومي للمندوب ${who} بواسطة ${opts.reviewerName}.`
      : (reason
        ? `تم رفض طلب تعديل الرقم القومي للمندوب ${who} بواسطة ${opts.reviewerName}. السبب: ${reason}`
        : `تم رفض طلب تعديل الرقم القومي للمندوب ${who} بواسطة ${opts.reviewerName}.`),
    type: "delegate_national_id_review",
    senderName: opts.reviewerName,
    senderRole: "reviewer",
    companyUID: opts.companyUID,
    organizationId: opts.organizationUID,
    isRead: false,
    requestId: opts.requestId,
    targetDelegateUid: opts.targetDelegateUid,
  };
}

