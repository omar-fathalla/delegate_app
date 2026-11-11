/**
 * Firestore transaction that applies a hold add/remove through holds.ts.
 * Shadow mode does not write status or statusReason.
 */
import {getAuth} from "firebase-admin/auth";
import {FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {
  HOLD_KEYS,
  authorityStatusFields,
  holdsMode,
  isHoldKey,
  isHoldOp,
  planHoldChange,
  shouldRevokeRefreshTokens,
  type HoldKey,
  type HoldOp,
  type HoldChangePlan,
} from "./holds";

type Db = FirebaseFirestore.Firestore;

export class HoldApplyError extends Error {
  constructor(public reason: string, public httpCode: "not-found" | "failed-precondition" | "invalid-argument" = "failed-precondition") {
    super(reason);
  }
}

export interface ApplyHoldArgs {
  orgId: string;
  companyId: string;
  uid: string;
  op: HoldOp;
  hold: HoldKey;
  actor: string;
  note?: string;
  requestId?: string;
  source?: string;
  periodCode?: string;
  cycleId?: string;
  at?: string;
  mode?: string;
  revokeRefreshTokens?: (uid: string) => Promise<void>;
}

function serializeHolds(holds: HoldChangePlan["nextHolds"]): Record<string, unknown> {
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

export async function applyHoldChange(db: Db, args: ApplyHoldArgs): Promise<HoldChangePlan> {
  if (!args.orgId || !args.companyId || !args.uid) {
    throw new HoldApplyError("invalid_target", "invalid-argument");
  }
  if (!isHoldKey(args.hold) || !isHoldOp(args.op)) {
    throw new HoldApplyError("invalid_hold", "invalid-argument");
  }
  const ref = db.doc(`organizations/${args.orgId}/companies/${args.companyId}/delegates/${args.uid}`);
  const at = args.at || new Date().toISOString();
  const mode = args.mode || holdsMode();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HoldApplyError("delegate_not_found", "not-found");
    const data = (snap.data() || {}) as Record<string, unknown>;
    const plan = planHoldChange({
      data,
      op: args.op,
      hold: args.hold,
      actor: args.actor,
      mode,
      note: args.note,
      requestId: args.requestId,
      at,
      source: args.source,
      periodCode: args.periodCode,
      cycleId: args.cycleId,
    });
    if (!plan.ok) throw new HoldApplyError(plan.reason || "failed_precondition");
    if (plan.unchanged) return plan;

    const update: Record<string, unknown> = {
      holds: serializeHolds(plan.nextHolds),
      statusVersion: plan.statusVersion,
      holdsAuthorityAt: at,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const statusWrite = authorityStatusFields(mode, plan.derivedStatus, plan.nextStatusReason);
    if (statusWrite) {
      update.status = statusWrite.status;
      update.statusReason = statusWrite.statusReason === null ?
        FieldValue.delete() : statusWrite.statusReason;
    }
    tx.update(ref, update as FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>);
    tx.set(ref.collection("statusHistory").doc(), {
      ...plan.history,
      writtenAt: FieldValue.serverTimestamp(),
    });
    return plan;
  }).then(async (plan) => {
    if (shouldRevokeRefreshTokens(plan)) {
      try {
        const revoke = args.revokeRefreshTokens ??
          ((uid: string) => getAuth().revokeRefreshTokens(uid));
        await revoke(args.uid);
      } catch (e) {
        logger.warn("revokeRefreshTokens failed after hold", {message: String(e)});
      }
    }
    return plan;
  });
}
