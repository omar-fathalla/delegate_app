/**
 * TAS-362: which check-ins are forgotten sessions, and what the job writes.
 *
 * A check-in with no check-out 11.5 h after it started is marked
 * `missingCheckOut: true` (no check-out time, so zero hours) and waits for HR
 * to set the check-out. The delegate gets one notification per session.
 */

/** Same window as the app (kAttendanceAutoCloseAfter). */
export const FORGOTTEN_AFTER_MS = (11 * 60 + 30) * 60 * 1000;
/** How far back the hourly job looks (older ones were handled by earlier runs). */
export const LOOKBACK_MS = 48 * 60 * 60 * 1000;

type Doc = Record<string, unknown> | null | undefined;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** The time window of check-ins the job queries: [now-48h, now-11.5h]. */
export function window(nowMs: number): {fromMs: number; toMs: number} {
  return {fromMs: nowMs - LOOKBACK_MS, toMs: nowMs - FORGOTTEN_AFTER_MS};
}

/**
 * True when the record is an open check-in old enough to be forgotten and not
 * handled yet. Firestore cannot query a missing field, so the job queries by
 * type + time and filters here.
 */
export function isForgotten(data: Doc, checkInMs: number | null, nowMs: number): boolean {
  const d = data || {};
  if (str(d.type) !== "check_in") return false;
  if (checkInMs == null || nowMs - checkInMs < FORGOTTEN_AFTER_MS) return false;
  if (d.checkOutTime != null) return false; // closed (by the delegate, HR, or an old app build)
  if (d.missingCheckOut === true || d.isAutoCheckOut === true) return false;
  return true;
}

/** Fields stamped on the check-in (the server timestamp is added by the caller). */
export function markFields(): Record<string, unknown> {
  return {missingCheckOut: true, missingCheckOutBy: "server"};
}

/** Delegate notification (message 3.17 in USER-SCENARIOS/01-delegate-messages.md). */
export function notificationFor(checkInId: string, data: Doc): {id: string; doc: Record<string, unknown>} | null {
  const d = data || {};
  const delegateId = str(d.delegateId) || str(d.userId);
  if (!delegateId) return null;
  const branch = str(d.branchName);
  const where = branch ? `في ${branch} ` : "";
  return {
    // One notification per session, whatever the number of runs.
    id: `missing_checkout_${checkInId}`,
    doc: {
      delegateUid: delegateId,
      organizationId: str(d.organizationId) || str(d.organizationUID),
      companyId: str(d.companyId) || str(d.companyUID),
      title: "ماسجلتش انصراف",
      body: `حضورك ${where}مالوش انصراف، فساعاته مش محسوبة لحد ما الـ HR يسجلها. كلّم المشرف.`,
      type: "attendance_missing_checkout",
      attendanceId: checkInId,
      isRead: false,
    },
  };
}
