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
  return id.length > 0 && !id.includes("/") && id.length <= 256;
}

export function staffKind(role: unknown): "global" | "company" | "none" {
  const r = str(role);
  if (GLOBAL_STAFF_ROLES.has(r)) return "global";
  if (COMPANY_STAFF_ROLES.has(r)) return "company";
  return "none";
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
 */
export function decideEnsureIntent(input: {
  authenticated: boolean;
  anonymous: boolean;
  role: unknown;
  callerCompany: unknown;
  requestedCompany: unknown;
  ownerCompany: string | null;
  lockedByIntent: boolean;
}): IntentDecision {
  if (!input.authenticated || input.anonymous) {
    return {ok: false, reason: "sign_in_required"};
  }
  const kind = staffKind(input.role);
  if (kind === "none") return {ok: false, reason: "caller_not_staff"};
  const callerCo = str(input.callerCompany);
  const requested = str(input.requestedCompany);
  const owner = input.ownerCompany ? str(input.ownerCompany) : "";

  if (owner) {
    if (kind === "company") {
      if (!callerCo) return {ok: false, reason: "caller_no_company"};
      if (callerCo !== owner) return {ok: false, reason: "folder_other_company"};
    }
    return {
      ok: true,
      action: input.lockedByIntent ? "reuse" : "create",
      companyUID: owner,
    };
  }

  // New folder: reserve for the caller's company. Global staff may pass a hint.
  const reserve = kind === "global" ? (requested || callerCo) : callerCo;
  if (!reserve) return {ok: false, reason: "company_required"};
  if (kind === "company" && requested && requested !== callerCo) {
    return {ok: false, reason: "company_mismatch"};
  }
  return {ok: true, action: "create", companyUID: reserve};
}
