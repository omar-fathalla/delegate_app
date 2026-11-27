/**
 * TAS-367: a new device-change request tells the company's supervisors (and
 * company admins) at once, whoever wrote it (the app's submitUnbindRequest or
 * delegateLoginV2 on a device mismatch). One notification per request.
 */
import {SUPERVISOR_BROADCAST_PREFIX} from "./supervisor_broadcast_push";

type Doc = Record<string, unknown> | null | undefined;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function unbindRequestNotification(requestId: string, data: Doc):
  {id: string; doc: Record<string, unknown>} | null {
  const d = data || {};
  const companyUID = str(d.companyUID) || str(d.companyId);
  if (!companyUID || str(d.status) !== "pending") return null;
  const name = str(d.delegateName) || "مندوب";
  const model = str(d.requestedDeviceModel);
  return {
    // Fixed id: a retried or second write of the same request sends nothing new.
    id: `unbind_request_${requestId}`,
    doc: {
      delegateUid: `${SUPERVISOR_BROADCAST_PREFIX}${companyUID}`,
      companyUID,
      companyId: companyUID,
      organizationUID: str(d.organizationUID) || str(d.organizationId),
      title: "طلب تغيير جهاز",
      body: `${name} طالب يدخل من جهاز جديد${model ? ` (${model})` : ""}. راجع الطلب من «فك ربط الأجهزة».`,
      type: "device_unbind_request",
      requestId,
      targetDelegateId: str(d.delegateUid),
      isRead: false,
    },
  };
}
