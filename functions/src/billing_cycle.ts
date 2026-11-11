/**
 * Pure helpers for startBillingCycle (Phase 2 item 2).
 * Replaces the web W7 client-side clearAllDeferredPayments$ fleet write.
 * Keep this file free of firebase-admin so unit tests can load it after tsc.
 */
import {normalizeRoleKey} from "./staff_phone_lookup_logic";
import {
  HOLD_BILLING_CYCLE_RESET,
  canonicalStatus,
  inferSource,
  parseHolds,
  type HoldsCaller,
} from "./holds";
import {periodOf} from "./subscription_logic";

export const BILLING_CYCLES = "billing_cycles";
export const BILLING_PHASE_COMPANIES = "companies";
export const BILLING_PHASE_DELEGATES = "delegates";
export const BILLING_STATE_RUNNING = "running";
export const BILLING_STATE_DONE = "done";
export const BILLING_PAGE_SIZE = 200;
export const BILLING_BATCH_OPS = 400;
export const BILLING_SOURCE = "startBillingCycle";

const SUPER = new Set(["super_admin", "superadmin"]);
const ORG_ADMIN = new Set(["organization_admin", "organizationadmin", "org_admin"]);
const COMPANY_ADMIN = new Set(["company_admin", "companyadmin", "admin"]);

const CYCLE_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;
const ORG_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

export type Decision = {ok: true} | {ok: false; reason: string};

export type BillingSkipReason =
  | "wrong_org"
  | "status_not_actionable"
  | "already_suspended"
  | "already_held"
  | "source_app"
  | "app_added_request"
  | "paid_subscription"
  | "paid_coverage";

export interface BillingCounts {
  docs: number;
  companies: number;
  companiesReset: number;
  written: number;
  skipped: number;
  byReason: Record<string, number>;
}

export interface BillingRunState {
  project?: string;
  orgId: string;
  cycleId: string;
  periodCode: string;
  state: "running" | "done";
  phase: "companies" | "delegates";
  cursor: string;
  actor: string;
  leaseUntil: number;
  companiesReset: boolean;
  counts: BillingCounts;
  mode: string;
  startedAt?: string;
  updatedAt?: string;
  finishedAt?: string;
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function emptyBillingCounts(): BillingCounts {
  return {
    docs: 0,
    companies: 0,
    companiesReset: 0,
    written: 0,
    skipped: 0,
    byReason: {},
  };
}

export function addCount(counts: BillingCounts, key: keyof BillingCounts, n = 1): void {
  if (key === "byReason") return;
  counts[key] = (counts[key] as number) + n;
}

export function addReason(counts: BillingCounts, reason: string, n = 1): void {
  counts.byReason[reason] = (counts.byReason[reason] || 0) + n;
  counts.skipped += n;
}

export function isValidOrgId(orgId: unknown): boolean {
  return ORG_ID_RE.test(str(orgId));
}

export function isValidCycleId(cycleId: unknown): boolean {
  return CYCLE_ID_RE.test(str(cycleId));
}

export function billingRunId(orgId: string, cycleId: string): string {
  return `${str(orgId)}_${str(cycleId)}`;
}

export function decideStartBillingCycle(
  caller: HoldsCaller,
  orgId: unknown,
  cycleId: unknown,
): Decision {
  if (!isValidOrgId(orgId)) return {ok: false, reason: "invalid_org"};
  if (!isValidCycleId(cycleId)) return {ok: false, reason: "invalid_cycle"};
  if (!str(caller.uid)) return {ok: false, reason: "sign_in_required"};
  if (caller.isActive === false) return {ok: false, reason: "caller_inactive"};

  const role = normalizeRoleKey(caller.role);
  const callerOrg = str(caller.organizationUID);
  const isSuper = SUPER.has(role);
  const isOrg = ORG_ADMIN.has(role);
  const isCompany = COMPANY_ADMIN.has(role);

  if (isCompany && !isSuper && !isOrg) return {ok: false, reason: "caller_not_allowed"};
  if (!isSuper && !isOrg) return {ok: false, reason: "caller_not_allowed"};
  if (!isSuper) {
    // Org admin: fail closed when organizationUID is empty or for another org.
    if (!callerOrg || callerOrg !== str(orgId)) return {ok: false, reason: "out_of_scope"};
  }
  return {ok: true};
}

export function parseDelegatePath(path: string): {orgId: string; companyId: string; uid: string} | null {
  const parts = str(path).split("/").filter((p) => p !== "");
  if (parts.length !== 6) return null;
  if (parts[0] !== "organizations" || parts[2] !== "companies" || parts[4] !== "delegates") {
    return null;
  }
  const orgId = parts[1];
  const companyId = parts[3];
  const uid = parts[5];
  if (!orgId || !companyId || !uid) return null;
  return {orgId, companyId, uid};
}

export function subscriptionPaidForPeriod(subscription: unknown, periodCode: string): boolean {
  if (!periodCode || !subscription || typeof subscription !== "object" || Array.isArray(subscription)) {
    return false;
  }
  const s = subscription as Record<string, unknown>;
  if (str(s.periodCode) !== periodCode) return false;
  const pay = str(s.paymentStatus).toLowerCase();
  return pay === "paid" || pay === "waived";
}

export function skipReasonForDelegate(
  path: string,
  data: Record<string, unknown>,
  orgId: string,
  periodCode: string,
  appAddedUids: Set<string>,
  coveredUids: Set<string>,
): BillingSkipReason | null {
  const parsed = parseDelegatePath(path);
  if (!parsed || parsed.orgId !== orgId) return "wrong_org";

  const status = canonicalStatus(data.status);
  if (status === "pending" || status === "rejected" || status === "") {
    return "status_not_actionable";
  }
  if (status === "suspended") return "already_suspended";

  if (parseHolds(data.holds)[HOLD_BILLING_CYCLE_RESET]) return "already_held";

  if (inferSource(data.delegateSource, data.source) === "app") return "source_app";

  const uid = str(data.uid) || parsed.uid;
  if (uid && appAddedUids.has(uid)) return "app_added_request";
  if (uid && coveredUids.has(uid)) return "paid_coverage";
  if (subscriptionPaidForPeriod(data.subscription, periodCode)) return "paid_subscription";
  return null;
}

export function companyResetData(): Record<string, unknown> {
  return {
    deferredPayment: 0,
    hasDeferredPayment: false,
    totalApprovedDelegates: 0,
  };
}

export type ClaimAction =
  | "create"
  | "resume"
  | "noop_done"
  | "in_progress";

export interface ClaimResult {
  action: ClaimAction;
  state: BillingRunState;
}

export function claimBillingRun(
  existing: BillingRunState | null,
  args: {
    orgId: string;
    cycleId: string;
    periodCode: string;
    actor: string;
    mode: string;
    nowMs: number;
    at: string;
    leaseMs?: number;
  },
): ClaimResult {
  const leaseMs = args.leaseMs ?? 120_000;
  if (!existing) {
    const state: BillingRunState = {
      orgId: args.orgId,
      cycleId: args.cycleId,
      periodCode: args.periodCode,
      state: BILLING_STATE_RUNNING,
      phase: BILLING_PHASE_COMPANIES,
      cursor: "",
      actor: args.actor,
      leaseUntil: args.nowMs + leaseMs,
      companiesReset: false,
      counts: emptyBillingCounts(),
      mode: args.mode,
      startedAt: args.at,
      updatedAt: args.at,
    };
    return {action: "create", state};
  }
  if (existing.state === BILLING_STATE_DONE) {
    return {action: "noop_done", state: existing};
  }
  const leaseValid = Number(existing.leaseUntil) > args.nowMs;
  if (leaseValid && existing.actor && existing.actor !== args.actor) {
    return {action: "in_progress", state: existing};
  }
  return {
    action: "resume",
    state: {
      ...existing,
      actor: args.actor,
      leaseUntil: args.nowMs + leaseMs,
      updatedAt: args.at,
      periodCode: existing.periodCode || args.periodCode,
      mode: existing.mode || args.mode,
    },
  };
}

export function yieldBillingRun(state: BillingRunState, at: string, nowMs: number): BillingRunState {
  return {...state, leaseUntil: nowMs, updatedAt: at};
}

export function finishBillingRun(state: BillingRunState, at: string, nowMs: number): BillingRunState {
  return {
    ...state,
    state: BILLING_STATE_DONE,
    phase: BILLING_PHASE_DELEGATES,
    cursor: "",
    leaseUntil: nowMs,
    companiesReset: true,
    finishedAt: at,
    updatedAt: at,
  };
}

export function periodCodeAt(at: Date): string {
  return periodOf(at).code;
}
