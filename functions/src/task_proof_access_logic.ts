/**
 * Pure helpers for delegate proof-of-work photos (Phase 4).
 * No I/O. Visibility is narrower than supervisor task images:
 * the uploading delegate, the task sender, and same-company
 * company supervisors/admins only.
 */
export const MAX_TASK_PROOF_IMAGES = 3;
export const TASK_PROOF_PURPOSE = "task_proof_image";
export const TASK_PROOF_ROOT = "task_proof";

const COMPANY_SUPERVISOR_ROLES = new Set([
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
]);

const PROOF_UPLOADER_ROLES = new Set([
  "delegate", "promoter", "field_delegate", "field-delegate",
  "marketing",
  "marketingPromotion", "marketing_promotion", "marketing-promotion",
  "marketingpromotion",
  "branches_marketing_manager", "branches-marketing-manager",
  "branches_marketing", "branchesMarketingManager",
  "branches-marketing", "branchesmarketingmanager",
]);

const BLOCKED_UPLOAD_STATUS = new Set([
  "pending", "rejected", "deleted", "disabled", "suspended", "inactive",
]);

export function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function normalizeTaskProofPath(path: unknown): string {
  return str(path).replace(/\\/g, "/").replace(/^\/+/, "");
}

export function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export type ParsedTaskProofPath = {
  companyId: string;
  uploaderUid: string;
  fileName: string;
};

/** N1-r: proof_{uid}_{token}.ext — a shorter uid cannot claim proof_{uid}_2_*. */
export function isOwnedProofFileName(fileName: unknown, uid: unknown): boolean {
  const id = str(uid);
  const name = str(fileName);
  if (!id || !name) return false;
  return new RegExp(`^proof_${escapeRegExp(id)}_[^_]+(\\.[A-Za-z0-9]+)?$`).test(name);
}

export function parseTaskProofPath(imagePath: unknown): ParsedTaskProofPath | null {
  const path = normalizeTaskProofPath(imagePath);
  const parts = path.split("/").filter(Boolean);
  if (parts.length !== 4 || parts[0] !== TASK_PROOF_ROOT) return null;
  const [ , companyId, uploaderUid, fileName] = parts;
  if (!companyId || !uploaderUid || !isOwnedProofFileName(fileName, uploaderUid)) {
    return null;
  }
  return {companyId, uploaderUid, fileName};
}

export function taskProofPathsFrom(raw: unknown): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  if (!Array.isArray(raw)) return out;
  for (const value of raw) {
    const path = normalizeTaskProofPath(value);
    if (!path || seen.has(path) || !parseTaskProofPath(path)) continue;
    seen.add(path);
    out.push(path);
    if (out.length >= MAX_TASK_PROOF_IMAGES) break;
  }
  return out;
}

export function isCompanySupervisorRole(role: unknown): boolean {
  return COMPANY_SUPERVISOR_ROLES.has(str(role));
}

export function isTaskProofUploaderRole(role: unknown): boolean {
  return PROOF_UPLOADER_ROLES.has(str(role));
}

export function isBlockedProofUploadStatus(status: unknown): boolean {
  const s = str(status).toLowerCase().replace(/-/g, "_");
  return s !== "" && BLOCKED_UPLOAD_STATUS.has(s);
}

export function canUploadTaskProof(input: {
  authenticated: boolean;
  anonymous: boolean;
  role: unknown;
  callerUid: unknown;
  callerCompany: unknown;
  requestedCompany: unknown;
  held: boolean;
  status?: unknown;
  isActive?: unknown;
}): {ok: true} | {ok: false; reason: string} {
  if (!input.authenticated || input.anonymous) {
    return {ok: false, reason: "sign_in_required"};
  }
  if (input.held || input.isActive === false || isBlockedProofUploadStatus(input.status)) {
    return {ok: false, reason: "caller_held"};
  }
  if (!isTaskProofUploaderRole(input.role)) {
    return {ok: false, reason: "not_allowed"};
  }
  const callerCo = str(input.callerCompany);
  const requested = str(input.requestedCompany);
  if (callerCo && requested && callerCo !== requested) {
    return {ok: false, reason: "company_mismatch"};
  }
  if (!callerCo && !requested) {
    return {ok: false, reason: "company_required"};
  }
  return {ok: true};
}

export function canReadTaskProof(input: {
  authenticated: boolean;
  anonymous: boolean;
  callerUid: unknown;
  callerRole: unknown;
  callerCompany: unknown;
  uploaderUid: unknown;
  taskCreatedBy: unknown;
  taskCompanyId: unknown;
  requestedPath: unknown;
  proofPaths: readonly string[];
  proofCompanyId?: unknown;
}): {ok: true} | {ok: false; reason: string} {
  if (!input.authenticated || input.anonymous) {
    return {ok: false, reason: "sign_in_required"};
  }
  const caller = str(input.callerUid);
  if (!caller) return {ok: false, reason: "sign_in_required"};
  const parsed = parseTaskProofPath(input.requestedPath);
  if (!parsed) return {ok: false, reason: "invalid_path"};
  const requested = normalizeTaskProofPath(input.requestedPath);
  const listed = input.proofPaths.map(normalizeTaskProofPath).filter(Boolean);
  if (!listed.includes(requested)) return {ok: false, reason: "path_mismatch"};
  const uploader = str(input.uploaderUid) || parsed.uploaderUid;
  if (uploader && parsed.uploaderUid !== uploader) {
    return {ok: false, reason: "path_mismatch"};
  }
  const taskCompany = str(input.taskCompanyId);
  const proofCompany = str(input.proofCompanyId) || parsed.companyId;
  if (!taskCompany || parsed.companyId !== taskCompany || (proofCompany && proofCompany !== taskCompany)) {
    return {ok: false, reason: "company_mismatch"};
  }
  if (caller === uploader) return {ok: true};
  if (caller === str(input.taskCreatedBy)) return {ok: true};
  if (isCompanySupervisorRole(input.callerRole) && str(input.callerCompany) === taskCompany) {
    return {ok: true};
  }
  return {ok: false, reason: "not_allowed"};
}

export function shouldStripTaskProofDownloadToken(objectName: unknown): boolean {
  return parseTaskProofPath(objectName) != null;
}

const ALL_TOKENS = new Set(["all", "الكل"]);
const BRANCH_MARKETING_TOKEN = "all_branch_marketing";
const MARKETING_PROMOTION_TOKEN = "all_marketing_promotion";

function lc(v: unknown): string {
  return str(v).toLowerCase().replace(/-/g, "_");
}

function isFieldDelegateProofRole(role: unknown): boolean {
  return lc(role) === "delegate";
}

function isBranchMarketingProofRole(role: unknown): boolean {
  return new Set([
    "marketing", "branches_marketing", "branchesmarketing",
    "branches_marketing_manager", "branchesmarketingmanager",
  ]).has(lc(role));
}

function isMarketingPromotionProofRole(role: unknown): boolean {
  return new Set(["marketing_promotion", "marketingpromotion"]).has(lc(role));
}

/**
 * B1: who may attach proof photos to a task. Only the task's assignee or
 * its intended recipients, in the task's org and company, and never on a
 * cancelled task. «الكل» is company field delegates only; sector tokens
 * accept the matching role (org-level sector staff with no company too).
 * Mirrors proofCallerMayWrite() in firestore.rules.
 */
export function canWriteTaskProof(input: {
  callerUid: unknown;
  callerRole: unknown;
  callerIds?: readonly unknown[];
  callerCompanyIds: readonly unknown[];
  callerOrgIds: readonly unknown[];
  organizationId: unknown;
  task: {companyId?: unknown; companyUID?: unknown; assignedTo?: unknown; status?: unknown} | null;
}): {ok: true} | {ok: false; reason: string} {
  const caller = str(input.callerUid);
  if (!caller) return {ok: false, reason: "sign_in_required"};
  const task = input.task;
  if (!task) return {ok: false, reason: "task_not_found"};
  if (str(task.status) === "cancelled") return {ok: false, reason: "task_cancelled"};
  const org = str(input.organizationId);
  const orgs = input.callerOrgIds.map(str).filter(Boolean);
  if (!org || !orgs.includes(org)) return {ok: false, reason: "org_mismatch"};
  const taskCo = str(task.companyId) || str(task.companyUID);
  if (!taskCo) return {ok: false, reason: "company_mismatch"};
  const cos = input.callerCompanyIds.map(str).filter(Boolean);
  const inCompany = cos.includes(taskCo);
  const assigned = str(task.assignedTo);
  if (!assigned) return {ok: false, reason: "not_assigned"};
  const ids = new Set([caller, ...(input.callerIds || []).map(str).filter(Boolean)]);
  const role = input.callerRole;
  if (ALL_TOKENS.has(assigned)) {
    if (!inCompany) return {ok: false, reason: "company_mismatch"};
    return isFieldDelegateProofRole(role) ? {ok: true} : {ok: false, reason: "not_assigned"};
  }
  if (assigned === BRANCH_MARKETING_TOKEN || assigned === MARKETING_PROMOTION_TOKEN) {
    const roleOk = assigned === BRANCH_MARKETING_TOKEN
      ? isBranchMarketingProofRole(role)
      : isMarketingPromotionProofRole(role);
    if (!roleOk) return {ok: false, reason: "not_assigned"};
    if (!inCompany && cos.length > 0) return {ok: false, reason: "company_mismatch"};
    return {ok: true};
  }
  if (!ids.has(assigned)) return {ok: false, reason: "not_assigned"};
  if (!inCompany) return {ok: false, reason: "company_mismatch"};
  if (!isTaskProofUploaderRole(role)) return {ok: false, reason: "not_allowed"};
  return {ok: true};
}

/**
 * Display name for a proofs doc, from the uploader's own profile. Never
 * from the client. Same order as the app's profile models.
 */
export function proofDisplayNameFrom(
  ...profiles: Array<Record<string, unknown> | null | undefined>
): string {
  for (const d of profiles) {
    if (!d) continue;
    const display = str(d.displayName);
    if (display) return display;
    const full = str(d.fullName);
    if (full) return full;
    const combined = [str(d.firstName), str(d.middleName), str(d.lastName)]
      .filter(Boolean).join(" ");
    if (combined) return combined;
    const name = str(d.name);
    if (name) return name;
  }
  return "";
}
