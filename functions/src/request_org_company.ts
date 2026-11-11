/**
 * Check that every organizationUID on a delegate request belongs to the
 * request's company. Used because the rules budget cannot exists() every
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
  return ids.slice(0, 10);
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
      ok: false, reason: "org_not_in_company", companyUID,
      orgIds: opts.orgIds, missing: opts.missing,
    };
  }
  return {ok: true, reason: "ok", companyUID, orgIds: opts.orgIds, missing: []};
}
