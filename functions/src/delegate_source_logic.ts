/**
 * Phase 1 item 1: infer delegateSource / chainOrigin (plan §5.4).
 * Pure helpers — no I/O, no Admin SDK. Used by stampDelegateSource and
 * the backfill script (after `npm run build`).
 */
import {isAppAddedRegistration} from "./subscription_logic";

export const SOURCE_FIELDS = [
  "delegateSource",
  "chainOrigin",
  "delegateSourceInferredBy",
  "delegateSourceAt",
  "delegateSourceRunId",
] as const;

export type DelegateSource = "web" | "app";
export type ChainOrigin =
  | "web_request"
  | "app_new_delegate"
  | "app_supervisor_copy"
  | "app_add_organization"
  | "unknown";
export type Confidence = "high" | "low" | "review";
export type InferRule = 1 | 2 | 3 | 4 | 5;

export type RequestEvidence = {
  id: string;
  requestType?: string;
  status?: string;
  supervisorUid?: string;
  existingDelegateUid?: string;
  organizationUID?: string;
};

export type ChainEvidence = {
  path: string;
  uid: string;
  organizationUID?: string;
  companyUID?: string;
  approvedRequestId?: string;
  registeredVia?: string;
  statusReason?: string;
  version?: unknown;
  alreadyStamped?: boolean;
};

export type WebCreateEvidence = {
  targetDelegateId: string;
  organizationUID?: string;
  companyUID?: string;
};

export type PersonInference = {
  uid: string;
  source: DelegateSource;
  rule: InferRule;
  confidence: Confidence;
};

const WEB_STATUS_REASONS = new Set([
  "create",
  "suspend",
  "activate",
  "billing_cycle_reset",
]);

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function isPendingOrRejectedAppRequest(data: RequestEvidence): boolean {
  const type = str(data.requestType || "new_delegate");
  const status = str(data.status).toLowerCase();
  return (
    type === "new_delegate" &&
    (status === "pending" || status === "rejected") &&
    str(data.supervisorUid) !== "" &&
    str(data.existingDelegateUid) === ""
  );
}

export function hasWebSignals(
  chains: ChainEvidence[],
  webCreates: WebCreateEvidence[],
  uid: string,
): boolean {
  if (webCreates.some((w) => str(w.targetDelegateId) === uid)) return true;
  return chains.some((c) => {
    const reason = str(c.statusReason);
    if (WEB_STATUS_REASONS.has(reason)) return true;
    return c.version !== undefined && c.version !== null && c.version !== "";
  });
}

export function inferPersonSource(input: {
  uid: string;
  appRequestById: RequestEvidence | null;
  chainDocs: ChainEvidence[];
  webCreates: WebCreateEvidence[];
}): PersonInference {
  const uid = str(input.uid);
  const req = input.appRequestById;

  if (req && isAppAddedRegistration(req.id, req as unknown as Record<string, unknown>)) {
    return {uid, source: "app", rule: 1, confidence: "high"};
  }
  if (req && isPendingOrRejectedAppRequest(req)) {
    return {uid, source: "app", rule: 2, confidence: "high"};
  }
  if (hasWebSignals(input.chainDocs, input.webCreates, uid)) {
    return {uid, source: "web", rule: 3, confidence: "high"};
  }
  if (input.chainDocs.some((c) => str(c.registeredVia) === "mobile_app")) {
    return {uid, source: "app", rule: 4, confidence: "low"};
  }
  return {uid, source: "web", rule: 5, confidence: "review"};
}

export function inferChainOrigin(input: {
  doc: ChainEvidence;
  person: PersonInference;
  supervisorOrgId?: string;
  requestOrgId?: string;
  hasAddOrganizationRequest?: boolean;
}): ChainOrigin {
  const {doc, person} = input;
  const approved = str(doc.approvedRequestId);
  const org = str(doc.organizationUID);
  const supervisorOrg = str(input.supervisorOrgId);
  const requestOrg = str(input.requestOrgId);

  if (person.rule === 1 || person.rule === 2) {
    // A copy in the supervisor's org is a supervisor copy even when
    // approvedRequestId equals the request/delegate id.
    if (supervisorOrg && org === supervisorOrg && requestOrg && org !== requestOrg) {
      return "app_supervisor_copy";
    }
    if (approved !== "" && approved === doc.uid) return "app_new_delegate";
    if (person.rule === 2) return "app_new_delegate";
    if (approved !== "" && approved !== doc.uid) return "app_add_organization";
    if (input.hasAddOrganizationRequest) return "app_add_organization";
    return "app_new_delegate";
  }

  if (person.rule === 3) {
    if (
      input.hasAddOrganizationRequest ||
      (approved !== "" && approved !== doc.uid) ||
      str(doc.registeredVia) === "mobile_app"
    ) {
      return "app_add_organization";
    }
    return "web_request";
  }

  return "unknown";
}

export type StampFields = {
  delegateSource: DelegateSource;
  chainOrigin: ChainOrigin;
  delegateSourceInferredBy: string;
  delegateSourceRunId: string;
};

export function stampPayload(
  origin: ChainOrigin,
  person: PersonInference,
  inferredBy: string,
  runId: string,
): StampFields {
  return {
    delegateSource: person.source,
    chainOrigin: origin,
    delegateSourceInferredBy: inferredBy,
    delegateSourceRunId: runId,
  };
}
