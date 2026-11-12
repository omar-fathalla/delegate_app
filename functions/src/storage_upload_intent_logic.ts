/**
 * Server-side storage_upload_intents: resolve the folder's owning company
 * (existing intent, request, or delegate uid) and decide whether the
 * caller may create or reuse the intent. Pure; no I/O.
 */
export const GLOBAL_STAFF_ROLES = new Set([
  "super-admin", "super_admin", "superadmin", "superAdmin",
  "Super-Admin", "SUPER_ADMIN",
  "technical_support", "technical-support", "technicalSupport",
  "technicalsupport", "tech_support", "techsupport",
]);

export const TASK_IMAGE_PURPOSE = "task_image";
export const TASK_PROOF_PURPOSE = "task_proof_image";

/** Roles that may send a task (and therefore attach an image). HR and accountant are out. */
export const TASK_ASSIGNER_ROLES = new Set([
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
  "organization-admin", "organization_admin", "organizationadmin",
  "organizationAdmin",
  "marketing",
  "marketingPromotion", "marketing_promotion", "marketing-promotion",
  "marketingpromotion",
  "branches_marketing_manager", "branches-marketing-manager",
  "branches_marketing", "branchesMarketingManager",
  "branches-marketing", "branchesmarketingmanager",
]);

export const COMPANY_STAFF_ROLES = new Set([
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
  "hr", "company-hr", "company_hr", "human_resources",
  "organization-admin", "organization_admin", "organizationadmin",
  "organizationAdmin",
]);

export type OwnerHit = {source: "intent" | "request" | "delegate"; companyUID: string};

export type IntentDecision =
  | {ok: true; action: "reuse"; companyUID: string}
  | {ok: true; action: "create"; companyUID: string}
  | {ok: false; reason: string};

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function normalizeFolderId(raw: unknown): string {
  return str(raw);
}

export function isValidFolderId(id: string): boolean {
  // Firestore document ids cannot be "." or ".." or contain "/".
  return id.length > 0
    && id.length <= 256
    && id !== "."
    && id !== ".."
    && !id.includes("/");
}

export function isInactiveStatus(value: unknown): boolean {
  const s = typeof value === "string" ? value.trim().toLowerCase().replace(/-/g, "_") : "";
  return s === "inactive" || s === "disabled" || s === "suspended" || s === "deleted";
}

export function staffKind(role: unknown): "global" | "company" | "none" {
  const r = str(role);
  if (GLOBAL_STAFF_ROLES.has(r)) return "global";
  if (COMPANY_STAFF_ROLES.has(r)) return "company";
  return "none";
}

export function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Intent / object name for a task image: exact task_{callerUid}_{token}.ext (N1-r). */
export function isTaskImageFolderId(folderId: string, callerUid: string): boolean {
  const id = str(callerUid);
  const name = str(folderId);
  if (!id || !name) return false;
  return new RegExp(`^task_${escapeRegExp(id)}_[^_]+(\\.[A-Za-z0-9]+)?$`).test(name);
}

export function isTaskImagePurpose(purpose: unknown): boolean {
  return str(purpose) === TASK_IMAGE_PURPOSE;
}

export function isTaskProofPurpose(purpose: unknown): boolean {
  return str(purpose) === TASK_PROOF_PURPOSE;
}

/** Intent / object name for a proof photo: exact proof_{callerUid}_{token}.ext (N1-r). */
export function isTaskProofFolderId(folderId: string, callerUid: string): boolean {
  const id = str(callerUid);
  const name = str(folderId);
  if (!id || !name) return false;
  return new RegExp(`^proof_${escapeRegExp(id)}_[^_]+(\\.[A-Za-z0-9]+)?$`).test(name);
}

const TASK_PROOF_UPLOADER_ROLES = new Set([
  "delegate", "promoter", "field_delegate", "field-delegate",
  "marketing",
  "marketingPromotion", "marketing_promotion", "marketing-promotion",
  "marketingpromotion",
  "branches_marketing_manager", "branches-marketing-manager",
  "branches_marketing", "branchesMarketingManager",
  "branches-marketing", "branchesmarketingmanager",
]);

export function isTaskProofUploaderRole(role: unknown): boolean {
  return TASK_PROOF_UPLOADER_ROLES.has(str(role));
}

/**
 * Task-image intents are limited to assigner roles (not HR / accountant).
 * Document-folder intents keep the original staffKind list.
 */
export function staffKindForPurpose(role: unknown, purpose: unknown): "global" | "company" | "none" {
  if (isTaskProofPurpose(purpose)) {
    // Tech support and super admin cannot mint proof uploads.
    return isTaskProofUploaderRole(role) ? "company" : "none";
  }
  if (isTaskImagePurpose(purpose)) {
    const r = str(role);
    if (GLOBAL_STAFF_ROLES.has(r)) return "global";
    if (TASK_ASSIGNER_ROLES.has(r)) return "company";
    return "none";
  }
  return staffKind(role);
}

/**
 * All known records for this folder must agree on the company. An existing
 * intent wins as the locked tenant. Conflicting companies are fail-closed.
 */
export function resolveOwningCompany(hits: OwnerHit[]):
  {ok: true; companyUID: string | null; lockedByIntent: boolean} |
  {ok: false; reason: string} {
  const intent = hits.find((h) => h.source === "intent" && str(h.companyUID));
  if (intent) {
    const co = str(intent.companyUID);
    const conflict = hits.some((h) => str(h.companyUID) && str(h.companyUID) !== co);
    if (conflict) return {ok: false, reason: "company_conflict"};
    return {ok: true, companyUID: co, lockedByIntent: true};
  }
  const companies = [...new Set(hits.map((h) => str(h.companyUID)).filter(Boolean))];
  if (companies.length > 1) return {ok: false, reason: "company_conflict"};
  if (companies.length === 1) return {ok: true, companyUID: companies[0], lockedByIntent: false};
  return {ok: true, companyUID: null, lockedByIntent: false};
}

/**
 * @param ownerCompany company already bound to the folder, or null if new
 * @param callerCompany the staff user's companyUID
 * @param requestedCompany optional client hint, used only for a new reservation by global staff
 *   (or by org-level task assigners with no companyUID)
 * @param purpose `task_image` reserves a task-image object name; default is a document folder
 */
export function decideEnsureIntent(input: {
  authenticated: boolean;
  anonymous: boolean;
  role: unknown;
  callerCompany: unknown;
  requestedCompany: unknown;
  ownerCompany: string | null;
  lockedByIntent: boolean;
  purpose?: unknown;
}): IntentDecision {
  if (!input.authenticated || input.anonymous) {
    return {ok: false, reason: "sign_in_required"};
  }
  const kind = staffKindForPurpose(input.role, input.purpose);
  if (kind === "none") return {ok: false, reason: "caller_not_staff"};
  const callerCo = str(input.callerCompany);
  const requested = str(input.requestedCompany);
  const owner = input.ownerCompany ? str(input.ownerCompany) : "";

  if (owner) {
    if (kind === "company") {
      if (!callerCo) {
        // Org-level marketing / org-admin may attach to a requested company
        // they already reserved; they cannot switch it.
        if ((isTaskImagePurpose(input.purpose) || isTaskProofPurpose(input.purpose)) && requested && requested === owner) {
          return {
            ok: true,
            action: input.lockedByIntent ? "reuse" : "create",
            companyUID: owner,
          };
        }
        return {ok: false, reason: "caller_no_company"};
      }
      if (callerCo !== owner) return {ok: false, reason: "folder_other_company"};
    }
    return {
      ok: true,
      action: input.lockedByIntent ? "reuse" : "create",
      companyUID: owner,
    };
  }

  // New folder: reserve for the caller's company. Global staff (and
  // org-level task assigners with no company) may pass a hint.
  const orgLevelAssigner = (isTaskImagePurpose(input.purpose) || isTaskProofPurpose(input.purpose)) && kind === "company" && !callerCo;
  const reserve = kind === "global" || orgLevelAssigner ? (requested || callerCo) : callerCo;
  if (!reserve) return {ok: false, reason: "company_required"};
  if (kind === "company" && callerCo && requested && requested !== callerCo) {
    return {ok: false, reason: "company_mismatch"};
  }
  return {ok: true, action: "create", companyUID: reserve};
}
