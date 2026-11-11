/**
 * Shared hold-authority helpers (Phase 2 item 1).
 *
 * Shadow mode is the default: writers may add/remove holds, history and
 * statusVersion, but they do not change `status` or `statusReason`. The
 * side-effect trigger only records mismatches / bypasses to status_audit.
 * Flip to authoritative later (Phase 2 item 4) via HOLDS_AUTHORITY_MODE.
 *
 * Keep this file free of firebase-admin so unit tests can load it after tsc.
 */
import {normalizeRoleKey} from "./staff_phone_lookup_logic";

export const HOLDS_MODE_SHADOW = "shadow";
export const HOLDS_MODE_AUTHORITATIVE = "authoritative";

export const HOLD_ADMIN_SUSPEND = "admin_suspend";
export const HOLD_SUBSCRIPTION_EXPIRED = "subscription_expired";
export const HOLD_BILLING_CYCLE_RESET = "billing_cycle_reset";

export const HOLD_KEYS = [
  HOLD_ADMIN_SUSPEND,
  HOLD_SUBSCRIPTION_EXPIRED,
  HOLD_BILLING_CYCLE_RESET,
] as const;

export type HoldKey = typeof HOLD_KEYS[number];

/** Highest priority first, for the legacy statusReason field. */
export const HOLD_PRIORITY: HoldKey[] = [
  HOLD_ADMIN_SUSPEND,
  HOLD_SUBSCRIPTION_EXPIRED,
  HOLD_BILLING_CYCLE_RESET,
];

const SUPER = new Set(["super_admin", "superadmin"]);
const ORG_ADMIN = new Set(["organization_admin", "organizationadmin", "org_admin"]);
const COMPANY_ADMIN = new Set([
  "company_admin",
  "companyadmin",
  "admin",
  "supervisor",
  "company_supervisor",
]);
const TECH_SUPPORT = new Set([
  "technical_support",
  "technicalsupport",
  "tech_support",
  "techsupport",
]);

export interface HoldEntry {
  at?: string;
  by?: string;
  source?: string;
  periodCode?: string;
  cycleId?: string;
  note?: string;
  requestId?: string;
}

export type Holds = Partial<Record<HoldKey, HoldEntry>>;

export interface HoldsCaller {
  uid: string;
  role: unknown;
  organizationUID?: unknown;
  companyUID?: unknown;
  isActive?: unknown;
}

export type HoldOp = "add" | "remove";

export type Decision = {ok: true} | {ok: false; reason: string};

export interface HoldChangeInput {
  data: Record<string, unknown>;
  op: HoldOp;
  hold: HoldKey;
  actor: string;
  mode: string;
  note?: string;
  requestId?: string;
  at: string;
  source?: string;
  periodCode?: string;
  cycleId?: string;
}

export interface HoldChangePlan {
  ok: boolean;
  reason?: string;
  unchanged?: boolean;
  mode: string;
  nextHolds: Holds;
  derivedStatus: string;
  nextStatusReason: string | null;
  statusVersion: number;
  history: Record<string, unknown>;
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function holdsMode(env: NodeJS.Dict<string> = process.env): string {
  return env.HOLDS_AUTHORITY_MODE === HOLDS_MODE_AUTHORITATIVE ?
    HOLDS_MODE_AUTHORITATIVE :
    HOLDS_MODE_SHADOW;
}

/**
 * Status fields written onto the delegate document for a hold change.
 * Shadow (the default) returns null so callers leave `status` and
 * `statusReason` alone. Authoritative returns the derived status and the
 * highest-priority remaining hold (or null, which callers should delete).
 * Any value other than "authoritative" is treated as shadow (fail closed).
 */
export function authorityStatusFields(
  mode: string,
  derivedStatus: string,
  nextStatusReason: string | null,
): {status: string; statusReason: string | null} | null {
  if (mode !== HOLDS_MODE_AUTHORITATIVE) return null;
  return {status: derivedStatus, statusReason: nextStatusReason};
}

export function isHoldKey(v: unknown): v is HoldKey {
  return typeof v === "string" && (HOLD_KEYS as readonly string[]).includes(v);
}

export function isHoldOp(v: unknown): v is HoldOp {
  return v === "add" || v === "remove";
}

export function normalizeStatus(status: unknown): string {
  return str(status).toLowerCase();
}

/** Legacy `approved` is treated as active when comparing derived status. */
export function canonicalStatus(status: unknown): string {
  const s = normalizeStatus(status);
  return s === "approved" ? "active" : s;
}

export function parseHolds(raw: unknown): Holds {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: Holds = {};
  const rec = raw as Record<string, unknown>;
  for (const key of HOLD_KEYS) {
    const entry = rec[key];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue;
    const e = entry as Record<string, unknown>;
    const parsed: HoldEntry = {};
    if (str(e.at)) parsed.at = str(e.at);
    if (str(e.by)) parsed.by = str(e.by);
    if (str(e.source)) parsed.source = str(e.source);
    if (str(e.periodCode)) parsed.periodCode = str(e.periodCode);
    if (str(e.cycleId)) parsed.cycleId = str(e.cycleId);
    if (str(e.note)) parsed.note = str(e.note);
    if (str(e.requestId)) parsed.requestId = str(e.requestId);
    out[key] = parsed;
  }
  return out;
}

export function hasAnyHold(holds: Holds): boolean {
  return HOLD_KEYS.some((k) => !!holds[k]);
}

/**
 * pending and rejected stay as they are. Otherwise
 * status = holds non-empty ? suspended : active.
 */
export function deriveStatus(currentStatus: unknown, holds: Holds): string {
  const s = canonicalStatus(currentStatus);
  if (s === "pending" || s === "rejected") return s;
  return hasAnyHold(holds) ? "suspended" : "active";
}

export function statusReasonFromHolds(holds: Holds): string | null {
  for (const key of HOLD_PRIORITY) {
    if (holds[key]) return key;
  }
  return null;
}

export function holdsEqual(a: Holds, b: Holds): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Map a legacy statusReason onto holds. Known web reasons: suspend, billing_cycle_reset. */
export function inferHoldsFromStatusReason(
  status: unknown,
  statusReason: unknown,
  at: string,
  by: string,
): Holds {
  const s = canonicalStatus(status);
  if (s === "pending" || s === "rejected" || s !== "suspended") return {};
  const reason = str(statusReason).toLowerCase().replace(/-/g, "_");
  const entry = (hold: HoldKey, extra?: Partial<HoldEntry>): Holds =>
    ({[hold]: {at, by, source: "backfill", ...extra}});
  if (reason === "subscription_expired") return entry(HOLD_SUBSCRIPTION_EXPIRED);
  if (reason === "billing_cycle_reset") return entry(HOLD_BILLING_CYCLE_RESET);
  // activate / create are not holds. A suspended doc with no useful reason
  // still gets admin_suspend so derived status matches the live status.
  if (reason === "activate" || reason === "create") {
    return entry(HOLD_ADMIN_SUSPEND, {note: "backfill_unknown"});
  }
  if (reason === "suspend" || reason === "admin_suspend" || reason === "manual") {
    return entry(HOLD_ADMIN_SUSPEND);
  }
  return entry(HOLD_ADMIN_SUSPEND, reason ? {note: `backfill:${reason.slice(0, 80)}`} : {note: "backfill_unknown"});
}

export function inferRejectionReason(
  status: unknown,
  statusReason: unknown,
  existing: unknown,
): string {
  if (str(existing)) return str(existing);
  if (normalizeStatus(status) !== "rejected") return "";
  const reason = str(statusReason);
  const key = reason.toLowerCase().replace(/-/g, "_");
  if (!reason) return "";
  if ((HOLD_KEYS as readonly string[]).includes(key)) return "";
  if (key === "suspend" || key === "activate" || key === "create") return "";
  return reason;
}

export function inferSource(delegateSource: unknown, source: unknown): string {
  const existing = str(source).toLowerCase();
  if (existing === "web" || existing === "app") return existing;
  const stamped = str(delegateSource).toLowerCase();
  if (stamped === "web" || stamped === "app") return stamped;
  return "";
}

export function decideSetDelegateHold(
  caller: HoldsCaller | null,
  target: {orgId: string; companyId: string},
  hold: unknown,
  op: unknown,
  note?: unknown,
): Decision {
  if (!caller) return {ok: false, reason: "caller_not_staff"};
  if (caller.isActive === false) return {ok: false, reason: "caller_inactive"};
  const orgId = str(target.orgId);
  const companyId = str(target.companyId);
  if (!orgId || !companyId || !str(caller.uid)) return {ok: false, reason: "invalid_target"};
  if (!isHoldKey(hold)) return {ok: false, reason: "invalid_hold"};
  if (!isHoldOp(op)) return {ok: false, reason: "invalid_op"};

  const role = normalizeRoleKey(caller.role);
  const callerOrg = str(caller.organizationUID);
  const callerCo = str(caller.companyUID);
  const isSuper = SUPER.has(role);
  const isTech = TECH_SUPPORT.has(role);
  const isOrg = ORG_ADMIN.has(role);
  const isCompany = COMPANY_ADMIN.has(role);

  if (!isSuper && !isTech && !isOrg && !isCompany) return {ok: false, reason: "caller_not_allowed"};
  if (isSuper || isTech) {
    // Super-admin and technical support are unrestricted in scope.
    // subscription_expired override stays super-admin only (below).
  } else if (isOrg) {
    if (!callerOrg || callerOrg !== orgId) return {ok: false, reason: "out_of_scope"};
  } else {
    // Company admin: fail closed when companyUID is empty.
    if (!callerOrg || callerOrg !== orgId) return {ok: false, reason: "out_of_scope"};
    if (!callerCo || callerCo !== companyId) return {ok: false, reason: "out_of_scope"};
  }

  if (hold === HOLD_SUBSCRIPTION_EXPIRED) {
    if (!isSuper) return {ok: false, reason: "hold_not_allowed"};
    if (op === "remove" && !str(note)) return {ok: false, reason: "note_required"};
  }
  if (hold === HOLD_BILLING_CYCLE_RESET && isCompany && !isSuper && !isOrg) {
    return {ok: false, reason: "hold_not_allowed"};
  }
  return {ok: true};
}

export function isActionableStatus(status: unknown): boolean {
  const s = canonicalStatus(status);
  return s !== "pending" && s !== "rejected";
}

/**
 * Legacy-suspended delegates often have no holds map. Infer holds from
 * statusReason (subscription_expired, admin_suspend, …) before add/remove
 * so removing admin_suspend cannot reactivate an expired subscription.
 */
export function seedHoldsFromLegacyStatus(
  data: Record<string, unknown>,
  at: string,
  by: string,
): {holds: Holds; seeded: boolean} {
  const parsed = parseHolds(data.holds);
  if (hasAnyHold(parsed)) return {holds: parsed, seeded: false};
  const inferred = inferHoldsFromStatusReason(data.status, data.statusReason, at, by);
  if (hasAnyHold(inferred)) return {holds: inferred, seeded: true};
  return {holds: parsed, seeded: false};
}

/** Revoke refresh tokens when an authoritative write leaves the delegate suspended. */
export function shouldRevokeRefreshTokens(plan: HoldChangePlan): boolean {
  return !!plan.ok &&
    plan.mode === HOLDS_MODE_AUTHORITATIVE &&
    plan.derivedStatus === "suspended" &&
    !plan.unchanged;
}

function basePlan(
  mode: string,
  current: Holds,
  status: unknown,
  statusVersion: number,
  extra: Partial<HoldChangePlan> = {},
): HoldChangePlan {
  return {
    ok: true,
    mode,
    nextHolds: current,
    derivedStatus: deriveStatus(status, current),
    nextStatusReason: statusReasonFromHolds(current),
    statusVersion,
    history: {},
    ...extra,
  };
}

export function planHoldChange(input: HoldChangeInput): HoldChangePlan {
  const mode = input.mode === HOLDS_MODE_AUTHORITATIVE ?
    HOLDS_MODE_AUTHORITATIVE : HOLDS_MODE_SHADOW;
  const seeded = seedHoldsFromLegacyStatus(input.data, input.at, "legacy");
  const current = seeded.holds;
  const status = input.data.status;
  const existingVersion = Number(input.data.statusVersion) || 0;
  if (!isActionableStatus(status)) {
    return {
      ok: false, reason: "status_not_actionable", mode, nextHolds: current,
      derivedStatus: deriveStatus(status, current),
      nextStatusReason: statusReasonFromHolds(current),
      statusVersion: existingVersion,
      history: {},
    };
  }
  // Persist inferred legacy holds even when the requested op is a no-op.
  const persistSeed = (reason: string, extraHistory: Record<string, unknown> = {}): HoldChangePlan => ({
    ok: true,
    reason,
    unchanged: false,
    mode,
    nextHolds: current,
    derivedStatus: deriveStatus(status, current),
    nextStatusReason: statusReasonFromHolds(current),
    statusVersion: existingVersion + 1,
    history: {
      from: str(status) || null,
      to: mode === HOLDS_MODE_AUTHORITATIVE ? deriveStatus(status, current) : (str(status) || null),
      derivedStatus: deriveStatus(status, current),
      holdAdded: null,
      holdRemoved: null,
      seededLegacyHolds: true,
      by: input.actor,
      source: input.source || "setDelegateHold",
      at: input.at,
      requestId: input.requestId || null,
      mode,
      note: input.note || null,
      ...extraHistory,
    },
  });
  if (input.op === "add" && current[input.hold]) {
    if (seeded.seeded) return persistSeed("legacy_holds_seeded");
    return basePlan(mode, current, status, existingVersion, {unchanged: true});
  }
  if (input.op === "remove" && !current[input.hold]) {
    if (seeded.seeded) return persistSeed("hold_not_present");
    return basePlan(mode, current, status, existingVersion, {
      unchanged: true,
      reason: "hold_not_present",
    });
  }
  const next: Holds = {...current};
  if (input.op === "add") {
    next[input.hold] = {
      at: input.at,
      by: input.actor,
      source: input.source || "setDelegateHold",
      ...(input.note ? {note: input.note} : {}),
      ...(input.requestId ? {requestId: input.requestId} : {}),
      ...(input.periodCode ? {periodCode: input.periodCode} : {}),
      ...(input.cycleId ? {cycleId: input.cycleId} : {}),
    };
  } else {
    delete next[input.hold];
  }
  const version = (Number(input.data.statusVersion) || 0) + 1;
  const derived = deriveStatus(status, next);
  const reason = statusReasonFromHolds(next);
  if (holdsEqual(current, next)) {
    return {
      ok: true, unchanged: true, mode, nextHolds: current,
      derivedStatus: deriveStatus(status, current),
      nextStatusReason: statusReasonFromHolds(current),
      statusVersion: Number(input.data.statusVersion) || 0,
      history: {},
    };
  }
  return {
    ok: true, mode, nextHolds: next, derivedStatus: derived,
    nextStatusReason: reason,
    statusVersion: version,
    history: {
      from: str(status) || null,
      to: mode === HOLDS_MODE_AUTHORITATIVE ? derived : (str(status) || null),
      derivedStatus: derived,
      holdAdded: input.op === "add" ? input.hold : null,
      holdRemoved: input.op === "remove" ? input.hold : null,
      by: input.actor,
      source: input.source || "setDelegateHold",
      at: input.at,
      requestId: input.requestId || null,
      mode,
      note: input.note || null,
    },
  };
}

export interface ShadowAuditDecision {
  audit: boolean;
  viaAuthority: boolean;
  payload?: Record<string, unknown>;
}

/**
 * Audit when status / statusReason / holds / statusVersion changed.
 * Never recommends a status correction — shadow mode only logs.
 */
export function evaluateShadowAudit(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): ShadowAuditDecision {
  const keys = ["status", "statusReason", "holds", "statusVersion", "holdsAuthorityAt"];
  const changed = keys.some((k) => JSON.stringify(before[k] ?? null) !== JSON.stringify(after[k] ?? null));
  if (!changed) return {audit: false, viaAuthority: false};

  const beforeHolds = parseHolds(before.holds);
  const afterHolds = parseHolds(after.holds);
  const derived = deriveStatus(after.status, afterHolds);
  const actual = canonicalStatus(after.status);
  const viaAuthority = str(after.holdsAuthorityAt) !== "" &&
    str(after.holdsAuthorityAt) !== str(before.holdsAuthorityAt);
  const mismatch = actual !== "pending" && actual !== "rejected" && actual !== derived;

  return {
    audit: true,
    viaAuthority,
    payload: {
      from: str(before.status) || null,
      to: str(after.status) || null,
      derivedStatus: derived,
      mismatch,
      viaAuthority,
      holdsBefore: beforeHolds,
      holdsAfter: afterHolds,
      statusReasonBefore: str(before.statusReason) || null,
      statusReasonAfter: str(after.statusReason) || null,
      statusVersionBefore: Number(before.statusVersion) || 0,
      statusVersionAfter: Number(after.statusVersion) || 0,
    },
  };
}

export interface BackfillPlan {
  skip: boolean;
  reason?: string;
  fields?: Record<string, unknown>;
  previous?: Record<string, unknown>;
}

export function planBackfill(
  data: Record<string, unknown>,
  at: string,
  runId: string,
): BackfillPlan {
  const currentHolds = parseHolds(data.holds);
  const alreadyHolds = hasAnyHold(currentHolds);
  const inferred = alreadyHolds ? currentHolds :
    inferHoldsFromStatusReason(data.status, data.statusReason, at, "backfill");
  const rejection = inferRejectionReason(data.status, data.statusReason, data.rejectionReason);
  const source = inferSource(data.delegateSource, data.source);
  const hasVersion = Number(data.statusVersion) > 0;

  const fields: Record<string, unknown> = {};
  const previous: Record<string, unknown> = {};

  if (!alreadyHolds && hasAnyHold(inferred)) {
    fields.holds = inferred;
    previous.holds = data.holds ?? null;
  }
  if (!str(data.rejectionReason) && rejection) {
    fields.rejectionReason = rejection;
    previous.rejectionReason = data.rejectionReason ?? null;
  }
  if (!str(data.source) && source) {
    fields.source = source;
    previous.source = data.source ?? null;
  }
  if (!hasVersion) {
    fields.statusVersion = 1;
    previous.statusVersion = data.statusVersion ?? null;
  }
  if (Object.keys(fields).length === 0) {
    return {skip: true, reason: "already_backfilled"};
  }
  fields.holdsBackfillRunId = runId;
  // Shadow backfill never writes status or statusReason.
  return {skip: false, fields, previous};
}
