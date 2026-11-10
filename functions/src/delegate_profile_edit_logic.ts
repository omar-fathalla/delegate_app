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
  source: "direct_edit" | "national_id_approval";
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
