/**
 * Pure rules for respondToPenalty (TAS-365).
 *
 * - acknowledge: the penalty's delegate, ISSUED → ACKNOWLEDGED ("اطلعت عليه").
 * - dispute: the penalty's delegate, from ISSUED or ACKNOWLEDGED only, within
 *   DISPUTE_WINDOW_DAYS of issuedAt, once per penalty, reason required.
 *   Never on DEDUCTED (already in a paid month).
 * - resolve: a super admin, or the chain admin of the penalty's chain
 *   (user decision 2026-11-27), DISPUTED → ISSUED (dispute rejected, deducted
 *   in the decision month: deductionMonth) or CANCELLED (dispute accepted),
 *   reason required.
 * The delegate's notification comes from the trigger (penalty_delegate_notify).
 */
import {DISPUTE_WINDOW_DAYS} from "./penalty_delegate_notify_logic";

export type PenaltyAction = "acknowledge" | "dispute" | "resolve";
export type Decision = "uphold" | "cancel";

export interface RespondInput {
  penaltyId: string;
  action: PenaltyAction;
  reason: string;
  decision: Decision | "";
}

export interface Denial {
  code: "invalid-argument" | "permission-denied" | "failed-precondition" | "not-found";
  reason: string;
  message: string;
}

export const MAX_REASON = 500;
const DAY_MS = 24 * 60 * 60 * 1000;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function isDenial(x: unknown): x is Denial {
  return typeof x === "object" && x !== null && "code" in x && "reason" in x;
}

export function parseRespondInput(data: unknown): RespondInput | Denial {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const penaltyId = str(d.penaltyId);
  if (!penaltyId || penaltyId.includes("/")) {
    return {code: "invalid-argument", reason: "bad_penalty", message: "الجزاء مش محدد."};
  }
  const action = str(d.action) as PenaltyAction;
  if (!["acknowledge", "dispute", "resolve"].includes(action)) {
    return {code: "invalid-argument", reason: "bad_action", message: "الطلب مش مفهوم."};
  }
  const reason = str(d.reason);
  if (reason.length > MAX_REASON) {
    return {code: "invalid-argument", reason: "reason_too_long",
      message: `السبب طويل، اكتبه في ${MAX_REASON} حرف أو أقل.`};
  }
  const decision = str(d.decision) as Decision | "";
  if (action === "resolve" && decision !== "uphold" && decision !== "cancel") {
    return {code: "invalid-argument", reason: "bad_decision", message: "اختار: الجزاء يفضل ولا يتلغي."};
  }
  return {penaltyId, action, reason, decision: action === "resolve" ? decision : ""};
}

/** Milliseconds of a Firestore Timestamp, a Date, an ISO string or a number. */
export function toMillis(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (v instanceof Date) return v.getTime();
  if (typeof v === "string") {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : t;
  }
  const o = v as {toMillis?: () => number; seconds?: number; _seconds?: number};
  if (typeof o.toMillis === "function") return o.toMillis();
  const s = o.seconds ?? o._seconds;
  return typeof s === "number" ? s * 1000 : null;
}

/**
 * When the penalty was issued: issuedAt (server-stamped since TAS-365),
 * else the final approval time, else its creation.
 */
export function issuedAtMillis(p: Record<string, unknown>): number | null {
  return toMillis(p.issuedAt) ?? toMillis(p.generalManagerApprovedAt) ?? toMillis(p.createdAt);
}

/** "YYYY-MM" in Cairo time: the payroll month of a dispute decision. */
export function cairoMonth(ms: number): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit",
  }).formatToParts(new Date(ms));
  const y = parts.find((p) => p.type === "year")?.value ?? "";
  const m = parts.find((p) => p.type === "month")?.value ?? "";
  return `${y}-${m}`;
}

const SUPER = new Set(["super_admin", "superadmin"]);
const ORG_ADMIN = new Set(["organization_admin", "organizationadmin", "org_admin"]);

function roleKey(token: Record<string, unknown> | undefined): string {
  return str(token?.role).toLowerCase().replace(/-/g, "_");
}

/**
 * Who may decide a dispute: a super admin, or a chain admin whose orgId
 * claim is the penalty's chain. Role and scope from the token claims (TAS-23).
 */
export function canResolve(token: Record<string, unknown> | undefined, penalty: Record<string, unknown>): boolean {
  const r = roleKey(token);
  if (SUPER.has(r)) return true;
  if (!ORG_ADMIN.has(r)) return false;
  const org = str(token?.orgId) || str(token?.organizationId);
  const pOrg = str(penalty.organizationId) || str(penalty.organizationUID);
  return org !== "" && org === pOrg;
}

export interface Caller {
  uid: string;
  delegateIds: string[];
  token: Record<string, unknown> | undefined;
  name: string;
}

export type Plan = {update: Record<string, unknown>; noop?: boolean; status: string};

/**
 * What respondToPenalty writes, or why it refuses. Timestamps are the
 * placeholder `NOW` (the caller swaps in a serverTimestamp).
 */
export const NOW = "__SERVER_TIMESTAMP__";

export function planResponse(input: RespondInput, penalty: Record<string, unknown> | null,
  caller: Caller, nowMs: number): Plan | Denial {
  if (!penalty) return {code: "not-found", reason: "not_found", message: "الجزاء ده مش موجود."};
  const status = str(penalty.status).toUpperCase();
  if (input.action === "resolve") {
    if (!canResolve(caller.token, penalty)) {
      return {code: "permission-denied", reason: "not_decider",
        message: "قرار الاعتراض للسوبر أدمن وأدمن السلسلة بس."};
    }
    if (status !== "DISPUTED") {
      return {code: "failed-precondition", reason: "not_disputed",
        message: "الجزاء ده مش عليه اعتراض مستني قرار."};
    }
    if (input.reason.length < 3) {
      return {code: "invalid-argument", reason: "reason_required", message: "اكتب سبب القرار."};
    }
    const uphold = input.decision === "uphold";
    return {
      status: uphold ? "ISSUED" : "CANCELLED",
      update: {
        status: uphold ? "ISSUED" : "CANCELLED",
        disputeResolution: uphold ? "upheld" : "cancelled",
        disputeResolutionReason: input.reason,
        disputeResolvedBy: caller.uid,
        disputeResolvedByName: caller.name,
        disputeResolvedAt: NOW,
        ...(uphold ? {deductionMonth: cairoMonth(nowMs)} : {}),
        updatedAt: NOW,
        notifyByServerAt: NOW,
      },
    };
  }

  const target = str(penalty.targetDelegateId);
  if (!target || !caller.delegateIds.includes(target)) {
    return {code: "permission-denied", reason: "not_owner", message: "الجزاء ده مش عليك."};
  }

  if (input.action === "acknowledge") {
    if (status === "ACKNOWLEDGED") return {status, update: {}, noop: true};
    if (status !== "ISSUED") {
      return {code: "failed-precondition", reason: "wrong_status",
        message: "الجزاء ده مش مستني منك تأكيد."};
    }
    return {
      status: "ACKNOWLEDGED",
      update: {status: "ACKNOWLEDGED", acknowledgedAt: NOW, acknowledgedBy: caller.uid, updatedAt: NOW},
    };
  }

  // dispute (8.2 / 8.3 in USER-SCENARIOS/01-delegate-messages.md)
  if (status === "DISPUTED" || toMillis(penalty.disputedAt) != null || str(penalty.disputeResolution)) {
    return {code: "failed-precondition", reason: "already_disputed",
      message: "اعترضت على الجزاء ده قبل كده."};
  }
  if (status === "DEDUCTED") {
    return {code: "failed-precondition", reason: "deducted",
      message: "الجزاء ده اتخصم خلاص، وماينفعش تعترض عليه. كلّم الـ HR."};
  }
  if (status !== "ISSUED" && status !== "ACKNOWLEDGED") {
    return {code: "failed-precondition", reason: "wrong_status",
      message: "ماينفعش تعترض على الجزاء ده دلوقتي."};
  }
  if (input.reason.length < 3) {
    return {code: "invalid-argument", reason: "reason_required", message: "اكتب سبب الاعتراض."};
  }
  const issued = issuedAtMillis(penalty);
  if (issued == null || nowMs > issued + DISPUTE_WINDOW_DAYS * DAY_MS) {
    return {code: "failed-precondition", reason: "window_closed",
      message: `مدة الاعتراض (${DISPUTE_WINDOW_DAYS} أيام من صدور الجزاء) خلصت. كلّم الـ HR.`};
  }
  return {
    status: "DISPUTED",
    update: {
      status: "DISPUTED",
      statusBeforeDispute: status,
      disputeReason: input.reason,
      disputedAt: NOW,
      disputedBy: caller.uid,
      updatedAt: NOW,
    },
  };
}
