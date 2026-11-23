/**
 * Check every organizationUID on a delegate request. Product decision
 * 2026-11-17 (relaxes MED-2): any company may request any chain and
 * approval registers the company there, so a chain only fails when it does
 * not exist, or is the hidden Fathalla chain and the company is not
 * already in it. Used because the rules budget cannot exists() every
 * secondary chain.
 */
export function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function requestCompanyId(data: Record<string, unknown>): string {
  return str(data.companyUID) || str(data.companyId);
}

export function requestOrganizationIds(data: Record<string, unknown>): string[] {
  const ids: string[] = [];
  const seen = new Set<string>();
  const add = (raw: unknown) => {
    const id = str(raw);
    if (!id || seen.has(id)) return;
    seen.add(id);
    ids.push(id);
  };
  if (Array.isArray(data.organizationUIDs)) {
    for (const item of data.organizationUIDs) add(item);
  }
  add(data.organizationUID);
  add(data.organizationId);
  // No chain cap any more (one payment per delegate); 100 is a sanity bound
  // that matches the delegate_requests rules.
  return ids.slice(0, 100);
}

export function summarizeOrgCompanyCheck(opts: {
  companyUID: string;
  orgIds: string[];
  missing: string[];
}): {ok: boolean; reason: string; companyUID: string; orgIds: string[]; missing: string[]} {
  const companyUID = str(opts.companyUID);
  if (!companyUID) {
    return {ok: false, reason: "missing_company", companyUID: "", orgIds: opts.orgIds, missing: opts.orgIds};
  }
  if (opts.orgIds.length === 0) {
    return {ok: true, reason: "no_orgs", companyUID, orgIds: [], missing: []};
  }
  if (opts.missing.length > 0) {
    return {
      ok: false, reason: "chain_not_available", companyUID,
      orgIds: opts.orgIds, missing: opts.missing,
    };
  }
  return {ok: true, reason: "ok", companyUID, orgIds: opts.orgIds, missing: []};
}

export const ORG_COMPANY_CHECK_KEYS = [
  "orgCompanyCheck",
  "orgCompanyCheckReason",
  "orgCompanyCheckMissing",
  "orgCompanyCheckAt",
] as const;

/** Chains hidden from every picker (Fathalla has its own website signup). */
export function isHiddenChain(uid: unknown, name: unknown): boolean {
  const n = str(name).toLowerCase();
  const u = str(uid).toLowerCase();
  return n.includes("fathalla") || n.includes("فتح الله") || n.includes("فتح_الله") ||
    u.includes("fathalla") || u.includes("فتح_الله");
}

/** A requested chain is available when it exists and is not hidden, or is
 * hidden but the company is already in it, or is the base (free) chain
 * (TAS-256: every new delegate goes there; approval registers the company). */
export function chainAvailableForRequest(opts: {
  orgExists: boolean;
  orgId: string;
  orgName: unknown;
  companyInChain: boolean;
  isBaseChain?: boolean;
}): boolean {
  if (!opts.orgExists) return false;
  if (opts.isBaseChain === true) return true;
  if (!isHiddenChain(opts.orgId, opts.orgName)) return true;
  return opts.companyInChain;
}

/** new_delegate and add_organization must be stamped ok before approval. */
export function requestApprovalRequiresOrgCheck(requestType: unknown): boolean {
  const type = str(requestType) || "new_delegate";
  return type === "new_delegate" || type === "add_organization";
}

/** True when this request may be approved (mark is ok, or the type is exempt). */
export function requestApprovalOrgCheckOk(data: Record<string, unknown>): boolean {
  if (!requestApprovalRequiresOrgCheck(data.requestType)) return true;
  return str(data.orgCompanyCheck) === "ok";
}

/** Parent company doc for a nested delegate path must exist. */
export function delegateCreateCompanyMissing(opts: {
  orgId: string;
  companyId: string;
  companyExists: boolean;
}): boolean {
  return !str(opts.orgId) || !str(opts.companyId) || !opts.companyExists;
}
