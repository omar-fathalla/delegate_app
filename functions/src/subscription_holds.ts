/**
 * M1/M2 hold plans: add or remove `subscription_expired` through holds.ts.
 * Shadow mode (the default) does not write status or statusReason.
 * Reactivation is renewal-payment only; other holds are left in place.
 *
 * Do not deploy suspendExpiredSubscriptions with this change.
 */
import {
  HOLD_KEYS,
  HOLD_SUBSCRIPTION_EXPIRED,
  authorityStatusFields,
  holdsMode,
  parseHolds,
  planHoldChange,
  type HoldChangePlan,
} from "./holds";
import {SUSPEND_REASON} from "./subscription_logic";

export const M1_SOURCE = "suspendExpiredSubscriptions";
export const M2_SOURCE = "applyPaidRequest";

type Data = Record<string, unknown>;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function serializeHolds(holds: HoldChangePlan["nextHolds"]): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of HOLD_KEYS) {
    const entry = holds[key];
    if (!entry) continue;
    const clean: Record<string, string> = {};
    for (const [k, v] of Object.entries(entry)) {
      if (typeof v === "string" && v) clean[k] = v;
    }
    out[key] = clean;
  }
  return out;
}

/**
 * A legacy M1 write left statusReason=subscription_expired and no holds
 * map. Treat that as an existing expiry hold so a paid renewal can clear it.
 */
/**
 * A legacy doc may be status=suspended with statusReason=admin_suspend
 * or device_unbind (or another non-expiry reason) and no holds map.
 * A paid renewal must not treat that as "no holds remain".
 */
export function legacyNonExpirySuspensionBlocksReactivation(data: Data): boolean {
  if (str(data.status) === "deleted") return true;
  const status = str(data.status);
  if (status !== "suspended" && status !== "") return false;
  const reason = str(data.statusReason);
  if (!reason || reason === SUSPEND_REASON) return false;
  return true;
}

/**
 * Shadow M1 (period start) and M2 (current-period payment) both
 * reactivate when the expiry hold is gone and no legacy non-expiry
 * suspension remains. Use this so the two paths stay consistent.
 */
export function shouldShadowReactivateAfterExpiryClear(data: Data, derivedStatus: string): boolean {
  if (derivedStatus !== "active") return false;
  if (legacyNonExpirySuspensionBlocksReactivation(data)) return false;
  const status = str(data.status);
  return status === "suspended" || status === "";
}

export function withLegacyExpiryHold(data: Data, at: string): {data: Data; inferred: boolean} {
  const holds = parseHolds(data.holds);
  if (holds[HOLD_SUBSCRIPTION_EXPIRED]) return {data, inferred: false};
  if (str(data.statusReason) !== SUSPEND_REASON) return {data, inferred: false};
  return {
    data: {
      ...data,
      holds: {
        ...holds,
        [HOLD_SUBSCRIPTION_EXPIRED]: {at, by: "legacy", source: "legacy"},
      },
    },
    inferred: true,
  };
}

export interface ExpiryHoldWrite {
  ok: boolean;
  unchanged: boolean;
  reason?: string;
  inferredLegacy: boolean;
  mode: string;
  plan: HoldChangePlan;
  update: Record<string, unknown>;
}

export function planExpiryHoldWrite(input: {
  data: Data;
  op: "add" | "remove";
  at: string;
  actor: string;
  source: string;
  periodCode?: string;
  requestId?: string;
  mode?: string;
  inferLegacyExpiry?: boolean;
  extra?: Record<string, unknown>;
}): ExpiryHoldWrite {
  const mode = input.mode || holdsMode();
  const inferred = input.op === "remove" && input.inferLegacyExpiry !== false ?
    withLegacyExpiryHold(input.data, input.at) : {data: input.data, inferred: false};
  const plan = planHoldChange({
    data: inferred.data,
    op: input.op,
    hold: HOLD_SUBSCRIPTION_EXPIRED,
    actor: input.actor,
    mode,
    at: input.at,
    source: input.source,
    periodCode: input.periodCode,
    requestId: input.requestId,
  });
  const empty: ExpiryHoldWrite = {
    ok: !!plan.ok, unchanged: !!plan.unchanged, reason: plan.reason,
    inferredLegacy: inferred.inferred, mode, plan, update: {},
  };
  if (!plan.ok || plan.unchanged) return empty;
  const update: Record<string, unknown> = {
    holds: serializeHolds(plan.nextHolds),
    statusVersion: plan.statusVersion,
    holdsAuthorityAt: input.at,
    ...(input.extra || {}),
  };
  const statusWrite = authorityStatusFields(mode, plan.derivedStatus, plan.nextStatusReason);
  if (statusWrite) {
    update.status = statusWrite.status;
    update.statusReason = statusWrite.statusReason;
  }
  return {...empty, update};
}

