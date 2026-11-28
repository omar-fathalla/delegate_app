/**
 * TAS-371: the delegate hears about a decision on its leave request or its
 * device-change request from the server, not from the staff member's phone
 * (that write could fail after the status changed, and then nobody knew).
 *
 * Only the pending → approved / rejected move counts, and only when the
 * staff app marked the change `notifyByServer: true`: older staff app builds
 * still write their own notification, so without the marker the delegate
 * would get two. Once those builds are forced out, the marker check and the
 * client write go away (rules). Fixed ids (`leave_<id>_<status>`,
 * `unbind_<id>_<status>`) make a retried event write nothing new.
 */
type Doc = Record<string, unknown> | null | undefined;

export type RequestKind = "leave" | "unbind";

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** The decision this change made, or null when it is not one to announce. */
export function decidedStatus(before: Doc, after: Doc): "approved" | "rejected" | null {
  const b = before || {};
  const a = after || {};
  if (str(b.status) !== "pending") return null;
  const s = str(a.status);
  if (s !== "approved" && s !== "rejected") return null;
  if (a.notifyByServer !== true) return null;
  return s;
}

const TEXT: Record<RequestKind, Record<"approved" | "rejected", {title: string; type: string}>> = {
  leave: {
    approved: {title: "تمت الموافقة على طلب الإجازة / العذر", type: "leave_approved"},
    rejected: {title: "تم رفض طلب الإجازة / العذر", type: "leave_rejected"},
  },
  unbind: {
    approved: {title: "تمت الموافقة على فك ربط جهازك", type: "device_unbound"},
    rejected: {title: "تم رفض طلب فك ربط الجهاز", type: "device_unbind_rejected"},
  },
};

function bodyFor(kind: RequestKind, status: "approved" | "rejected", a: Record<string, unknown>): string {
  const reason = str(a.rejectReason);
  if (kind === "leave") {
    return status === "approved" ?
      "تم اعتماد طلبك من قِبل إدارة الشركة." :
      (reason ? `تم رفض طلبك: ${reason}` : "تم رفض طلبك.");
  }
  return status === "approved" ?
    "تم فك ربط هاتفك القديم بنجاح. يمكنك الآن تسجيل الدخول من جهازك الجديد وسيتم اعتماده تلقائياً." :
    (reason || "تم رفض طلب فك ارتباط الجهاز من قبل الإدارة");
}

/** The notification for this decision, or null. */
export function decisionNotification(kind: RequestKind, requestId: string, before: Doc, after: Doc):
  {id: string; doc: Record<string, unknown>} | null {
  const status = decidedStatus(before, after);
  if (!status) return null;
  const a = after || {};
  const delegateUid = str(a.delegateUid);
  if (!delegateUid) return null;
  const org = str(a.organizationUID) || str(a.organizationId);
  const co = str(a.companyUID) || str(a.companyId);
  const t = TEXT[kind][status];
  return {
    id: `${kind}_${requestId}_${status}`,
    doc: {
      delegateUid,
      // Both spellings: the app reads organizationUID, onNotificationCreated
      // reads organizationId.
      ...(org ? {organizationUID: org, organizationId: org} : {}),
      ...(co ? {companyUID: co, companyId: co} : {}),
      title: t.title,
      body: bodyFor(kind, status, a),
      type: t.type,
      requestId,
      isRead: false,
      createdBy: "system",
      senderName: str(a.resolvedByName),
    },
  };
}
