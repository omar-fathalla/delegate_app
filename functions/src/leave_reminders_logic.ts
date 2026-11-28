/**
 * TAS-370 (L-4): a leave request still pending after 24 hours reminds the
 * company's HR and supervisors (user decision 2026-11-27). Pure logic; the
 * hourly job is in leave_reminders.ts.
 */
import {SUPERVISOR_BROADCAST_PREFIX} from "./supervisor_broadcast_push";

type Doc = Record<string, unknown> | null | undefined;

export const REMIND_AFTER_MS = 24 * 3600 * 1000;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Pending for more than 24 h ([createdAtMs] null = not written yet). */
export function isOverdue(data: Doc, createdAtMs: number | null, nowMs: number): boolean {
  const d = data || {};
  if (str(d.status) !== "pending") return false;
  if (createdAtMs == null) return false;
  return nowMs - createdAtMs >= REMIND_AFTER_MS;
}

const INACTIVE = new Set(["suspended", "rejected", "deleted", "inactive", "disabled"]);

/** HR staff of the company (role "hr", any case), active only. */
export function isActiveHr(user: Doc): boolean {
  const u = user || {};
  return str(u.role).toLowerCase() === "hr" && !INACTIVE.has(str(u.status).toLowerCase());
}

export interface Reminder {id: string; doc: Record<string, unknown>}

/**
 * One notification for the supervisors' broadcast and one per HR user. Fixed
 * ids (leave_reminder_<id>, leave_reminder_<id>_<hrUid>): the hourly job may
 * see the same request again and sends nothing twice.
 */
export function reminderNotifications(leaveId: string, data: Doc, hrUids: string[]): Reminder[] {
  const d = data || {};
  const companyUID = str(d.companyUID);
  if (!companyUID) return [];
  const name = str(d.delegateName) || "مندوب";
  const base = {
    companyUID,
    companyId: companyUID,
    organizationUID: str(d.organizationUID),
    title: "طلب إجازة لسه مستني",
    body: `طلب ${name} مستني ردّ من أكتر من 24 ساعة. راجعه من «الإجازات».`,
    type: "leave_request_reminder",
    leaveRequestId: leaveId,
    targetDelegateId: str(d.delegateUid),
    isRead: false,
  };
  const out: Reminder[] = [{
    id: `leave_reminder_${leaveId}`,
    doc: {...base, delegateUid: `${SUPERVISOR_BROADCAST_PREFIX}${companyUID}`},
  }];
  for (const uid of Array.from(new Set(hrUids)).sort()) {
    if (!uid) continue;
    out.push({id: `leave_reminder_${leaveId}_${uid}`, doc: {...base, delegateUid: uid}});
  }
  return out;
}
