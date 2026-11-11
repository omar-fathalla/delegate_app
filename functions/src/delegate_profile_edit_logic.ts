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

/** Mohamed's decision: SA and tech support may also edit delegate data. */
export function canCallEditDelegateProfile(role: unknown): boolean {
  return isEditorRole(role) || isReviewerRole(role);
}

/** Global editors (SA / tech) are not company-scoped. */
export function profileEditCompanyScope(
  role: unknown,
  callerCompanyUID: string,
  targetCompanyUID: string,
): CompanyScopeResult {
  if (isReviewerRole(role)) return "ok";
  return companyScopeDecision(callerCompanyUID, targetCompanyUID);
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
  source: "direct_edit" | "national_id_approval" | "national_id_rejection" | "national_id_submission";
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

/** Default buckets for tashil-dev and prod only (not any *.appspot.com host). */
export const ALLOWED_STORAGE_BUCKETS = [
  "tashil-dev.appspot.com",
  "tashil-dev.firebasestorage.app",
  "practice-firebase-72df1.appspot.com",
  "practice-firebase-72df1.firebasestorage.app",
] as const;

export function isAllowedStorageBucket(bucketOrHost: string): boolean {
  return (ALLOWED_STORAGE_BUCKETS as readonly string[]).includes(
    String(bucketOrHost || "").toLowerCase(),
  );
}

/** https default-bucket Storage URLs, or delegate_documents/{uid}/... paths. */
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
    if (host === "firebasestorage.googleapis.com") {
      const m = u.pathname.match(/^\/v0\/b\/([^/]+)\//);
      return !!(m && isAllowedStorageBucket(decodeURIComponent(m[1])));
    }
    if (host === "storage.googleapis.com") {
      const seg = u.pathname.split("/").filter(Boolean)[0] || "";
      return isAllowedStorageBucket(decodeURIComponent(seg));
    }
    return isAllowedStorageBucket(host);
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

/** Role spellings that must receive privileged SA/tech alerts (N-4). */
export const PRIVILEGED_ALERT_ROLE_VALUES = [
  "super-admin", "super_admin", "superAdmin", "superadmin",
  "technicalSupport", "technical-support", "technical_support", "technicalsupport",
] as const;

export type ReviewTargetCheck = "ok" | "missing" | "mismatch" | "inactive";

export type ReviewTargetClass =
  | "matching_delegate"
  | "open_request"
  | "delegate_mismatch"
  | "delegate_inactive"
  | "skip";

/**
 * Re-read the live delegate and confirm it is the person named on the
 * submitted request, in the same company, and still active.
 */
export function reviewTargetMatchesSubmission(opts: {
  requestDelegateUid: string;
  requestCompanyUID: string;
  liveExists: boolean;
  livePath: string;
  liveData?: {uid?: unknown; companyUID?: unknown; companyId?: unknown; status?: unknown};
}): ReviewTargetCheck {
  if (!opts.liveExists || !opts.liveData) return "missing";
  const wantUid = String(opts.requestDelegateUid || "").trim();
  const wantCo = String(opts.requestCompanyUID || "").trim();
  if (!wantUid || !wantCo) return "mismatch";
  const data = opts.liveData;
  const pathId = opts.livePath.split("/").filter(Boolean).pop() || "";
  const liveUid = String(data.uid || "").trim() || pathId;
  const liveCo = String(data.companyUID || data.companyId || "").trim();
  if (liveUid !== wantUid || liveCo !== wantCo) return "mismatch";
  if (!isPatchableTarget(wantCo, data, opts.livePath)) return "mismatch";
  const st = String(data.status || "").toLowerCase();
  if (st && st !== "active" && st !== "approved") return "inactive";
  return "ok";
}

/**
 * Classify a collected review target: live delegates stay strictly
 * verified, but an open same-delegate request (e.g. add_organization)
 * should still receive the new national ID (N-9).
 */
export function classifyReviewTarget(opts: {
  requestDelegateUid: string;
  requestCompanyUID: string;
  nidRequestId?: string;
  liveExists: boolean;
  livePath: string;
  liveData?: {
    uid?: unknown;
    companyUID?: unknown;
    companyId?: unknown;
    status?: unknown;
    requestType?: unknown;
    actionType?: unknown;
    existingDelegateUid?: unknown;
    delegateUid?: unknown;
  };
}): ReviewTargetClass {
  const path = opts.livePath || "";
  if (path.includes("/delegates/")) {
    const check = reviewTargetMatchesSubmission(opts);
    if (check === "ok") return "matching_delegate";
    if (check === "inactive") return "delegate_inactive";
    if (check === "mismatch") return "delegate_mismatch";
    return "skip";
  }
  if (!/(^|\/)delegate_requests\//.test(path) && !path.startsWith("delegate_requests/")) {
    return "skip";
  }
  if (!opts.liveExists || !opts.liveData) return "skip";
  const pathId = path.split("/").filter(Boolean).pop() || "";
  if (opts.nidRequestId && pathId === opts.nidRequestId) return "skip";
  const data = opts.liveData;
  const reqType = String(data.requestType || data.actionType || "");
  if (reqType === "update_national_id") return "skip";
  const st = String(data.status || "").toLowerCase();
  const isSelfRegistration = reqType === "new" || reqType === "new_delegate"
    || reqType === "newDelegate";
  const isOpen = !st || st === "pending" || st === "open";
  const isApprovedRegistration = st === "approved" && isSelfRegistration;
  if (!isOpen && !isApprovedRegistration) return "skip";
  const wantUid = String(opts.requestDelegateUid || "").trim();
  const wantCo = String(opts.requestCompanyUID || "").trim();
  if (!wantUid || !wantCo) return "skip";
  const liveUid = String(
    data.existingDelegateUid || data.delegateUid || data.uid || "",
  ).trim() || pathId;
  if (liveUid !== wantUid) return "skip";
  if (!isPatchableTarget(wantCo, data, path)) return "skip";
  return "open_request";
}

/** Patch for users/{delegateUid} so login/wallet lookups stay in sync (N-5). */
export function usersProfileSyncPatch(fields: ProfileEditInput): Record<string, string> | null {
  const patch: Record<string, string> = {};
  if (fields.fullName) {
    const parts = splitFullName(fields.fullName);
    patch.fullName = fields.fullName;
    if (parts.firstName) patch.firstName = parts.firstName;
    if (parts.secondName) patch.secondName = parts.secondName;
    if (parts.thirdName) patch.thirdName = parts.thirdName;
  }
  if (fields.phoneNumber) {
    patch.phoneNumber = fields.phoneNumber;
    patch.phone = fields.phoneNumber;
  }
  if (fields.personalPhotoURL) {
    patch.personalPhotoURL = fields.personalPhotoURL;
    patch.profileImageUrl = fields.personalPhotoURL;
    patch.photoURL = fields.personalPhotoURL;
  }
  return Object.keys(patch).length ? patch : null;
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
  reviewerRole?: string;
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
    senderRole: String(opts.reviewerRole || "").trim() || "super-admin",
    companyUID: opts.companyUID,
    organizationId: opts.organizationUID,
    isRead: false,
    requestId: opts.requestId,
    targetDelegateUid: opts.targetDelegateUid,
  };
}

