/**
 * FCM data payload for a notification doc (onNotificationCreated).
 * TAS-34: photo-permission triggers no longer push themselves, so the doc's
 * permissionId must ride along here for the app to open the right request.
 */
export function pushDataFor(
  notification: Record<string, unknown>,
  fallbackType: string,
): Record<string, string> {
  const str = (v: unknown) => (typeof v === "string" ? v : v == null ? "" : String(v));
  const data: Record<string, string> = {
    type: str(notification.type) || fallbackType,
    organizationId: str(notification.organizationId),
    companyId: str(notification.companyId),
    taskId: str(notification.taskId),
  };
  const permissionId = str(notification.permissionId);
  if (permissionId) data.permissionId = permissionId;
  return data;
}
