/**
 * TAS-365: the delegate hears about its penalties from the server, not from
 * the staff member's phone (that write could fail after the status changed).
 *
 * Which moves the delegate hears about:
 * - the penalty reaches ISSUED (created ISSUED, e.g. createSupervisorPenalty,
 *   or approved later). A normal penalty starts PENDING_BRANCHES_MARKETING
 *   and is not announced until it is issued (it may still be rejected).
 * - an issued penalty is cancelled, or deducted.
 * - the decision on its dispute (DISPUTED → ISSUED: dispute rejected,
 *   DISPUTED → CANCELLED: dispute accepted).
 * A confidential penalty still reaches its delegate; confidentiality is for
 * the supervisors' and branches' channels only.
 *
 * When the penalty goes DISPUTED, the chain admins (named) and the super
 * admins (role broadcast) hear about it, since they decide.
 *
 * Fixed ids (`penalty_<id>_del_<kind>`) with create(): a retried event
 * writes nothing new.
 *
 * Older staff app builds still write the delegate's notification themselves.
 * A change that this server or a new app made carries `notifyByServerAt`
 * equal to `updatedAt` (one serverTimestamp in the same write), so it is
 * announced at once. Any other change (an old app) is announced only when no
 * notification for this penalty and delegate was written around the change
 * (the caller checks after a short wait).
 */
type Doc = Record<string, unknown> | null | undefined;

export type DelegatePenaltyEvent =
  | "issued"
  | "cancelled"
  | "deducted"
  | "dispute_rejected"
  | "dispute_accepted";

export const DISPUTE_WINDOW_DAYS = 3;

const ISSUED_LIKE = new Set(["ISSUED", "ACKNOWLEDGED", "DEDUCTED"]);

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function status(d: Doc): string {
  return str((d || {}).status).toUpperCase();
}

/** The move the delegate hears about, or null. `before` is null on create. */
export function delegatePenaltyEvent(before: Doc, after: Doc): DelegatePenaltyEvent | null {
  if (!after) return null;
  const a = status(after);
  const b = before ? status(before) : "";
  if (before && a === b) return null;
  if (a === "ISSUED") return b === "DISPUTED" ? "dispute_rejected" : "issued";
  if (a === "CANCELLED") {
    if (b === "DISPUTED") return "dispute_accepted";
    return ISSUED_LIKE.has(b) ? "cancelled" : null;
  }
  if (a === "DEDUCTED") return b === "ISSUED" || b === "ACKNOWLEDGED" ? "deducted" : null;
  return null;
}

/** The move into DISPUTED (the deciders are told). */
export function disputeOpened(before: Doc, after: Doc): boolean {
  return !!before && !!after && status(after) === "DISPUTED" && status(before) !== "DISPUTED";
}

/**
 * True when the server or a new app made this change and nobody else wrote
 * the delegate's notification: same serverTimestamp on both fields.
 */
export function changeMarkedForServer(after: Doc): boolean {
  const a = after || {};
  const m = a.notifyByServerAt as {isEqual?: (o: unknown) => boolean} | undefined;
  const u = a.updatedAt;
  if (!m || !u) return false;
  if (typeof m.isEqual === "function") return m.isEqual(u);
  return JSON.stringify(m) === JSON.stringify(u);
}

export function delegateNotificationId(penaltyId: string, event: DelegatePenaltyEvent): string {
  return `penalty_${penaltyId}_del_${event}`;
}

function fineText(p: Record<string, unknown>): string {
  const fine = Number(p.fineAmount) || 0;
  return Number.isInteger(fine) ? String(fine) : fine.toFixed(2);
}

/** USER-SCENARIOS/01-delegate-messages.md 8.1 and 8.4. */
export function delegatePenaltyMessage(
  event: DelegatePenaltyEvent,
  p: Record<string, unknown>,
): {title: string; body: string} {
  const title = str(p.title) || "جزاء";
  const fine = fineText(p);
  switch (event) {
  case "issued": {
    const by = str(p.createdByName) || "الإدارة";
    return {
      title: "عليك جزاء جديد",
      body: `${title}، ${fine} ج، من ${by}. لو شايف إنه غلط تقدر تعترض خلال ${DISPUTE_WINDOW_DAYS} أيام.`,
    };
  }
  case "dispute_accepted":
    return {title: "اعتراضك اتقبل والجزاء اتلغى", body: `${title}، ${fine} ج: مش هيتخصم.`};
  case "dispute_rejected": {
    const reason = str(p.disputeResolutionReason);
    return {
      title: "اعتراضك اترفض",
      body: `${title}، ${fine} ج: هيتخصم من مرتب الشهر ده.${reason ? ` السبب: ${reason}` : ""}`,
    };
  }
  case "cancelled":
    return {title: "الجزاء اتلغى", body: `${title}، ${fine} ج: مش هيتخصم.`};
  case "deducted":
    return {title: "الجزاء اتخصم", body: `${title}، ${fine} ج اتخصموا من مرتبك.`};
  }
}

function tenant(p: Record<string, unknown>): Record<string, string> {
  const org = str(p.organizationId) || str(p.organizationUID);
  const co = str(p.companyId) || str(p.companyUID);
  return {
    // Both spellings: the app reads organizationUID, onNotificationCreated
    // reads organizationId.
    ...(org ? {organizationUID: org, organizationId: org} : {}),
    ...(co ? {companyUID: co, companyId: co} : {}),
  };
}

/** The delegate's notification for this change, or null. createdAt added by the caller. */
export function delegatePenaltyNotification(penaltyId: string, before: Doc, after: Doc):
  {id: string; event: DelegatePenaltyEvent; delegateUid: string; doc: Record<string, unknown>} | null {
  const event = delegatePenaltyEvent(before, after);
  if (!event) return null;
  const a = after || {};
  const delegateUid = str(a.targetDelegateId);
  if (!delegateUid) return null;
  const {title, body} = delegatePenaltyMessage(event, a);
  return {
    id: delegateNotificationId(penaltyId, event),
    event,
    delegateUid,
    doc: {
      ...tenant(a),
      delegateUid,
      title,
      body,
      type: "penalty",
      penaltyEvent: event,
      penaltyId,
      companyName: str(a.companyName),
      branchId: a.branchId ?? null,
      branchName: a.branchName ?? null,
      targetDelegateId: delegateUid,
      targetDelegateName: a.targetDelegateName ?? null,
      fineAmount: Number(a.fineAmount) || 0,
      senderName: str(a.createdByName),
      createdBy: "system",
      isRead: false,
      read: false,
      deletedBy: [],
    },
  };
}

/** Notification fields for the deciders when a dispute opens. */
export function disputeOpenedNotification(penaltyId: string, p: Record<string, unknown>,
  delegateUid: string): Record<string, unknown> {
  const who = str(p.targetDelegateName) || "مندوب";
  const reason = str(p.disputeReason);
  return {
    ...tenant(p),
    delegateUid,
    title: "اعتراض على جزاء",
    body: `${who} اعترض على جزاء (${str(p.title)}، ${fineText(p)} ج).${reason ? ` السبب: ${reason}` : ""} محتاج قرار.`,
    type: "penalty",
    penaltyEvent: "dispute_opened",
    penaltyId,
    companyName: str(p.companyName),
    targetDelegateId: p.targetDelegateId ?? null,
    targetDelegateName: p.targetDelegateName ?? null,
    fineAmount: Number(p.fineAmount) || 0,
    senderName: who,
    createdBy: "system",
    isRead: false,
    read: false,
    deletedBy: [],
  };
}

export interface NotificationLike {
  delegateUid?: unknown;
  createdAtMs?: number | null;
}

/**
 * Old-app dedupe: true when a notification for this penalty and delegate
 * was written from `sinceMs` on (the old staff app writes it right after the
 * status change).
 */
export function clientAlreadyNotified(existing: NotificationLike[], delegateUid: string,
  sinceMs: number): boolean {
  return existing.some((n) => str(n.delegateUid) === delegateUid &&
    typeof n.createdAtMs === "number" && n.createdAtMs >= sinceMs);
}
