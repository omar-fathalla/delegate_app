/**
 * TAS-397: who hears about a «مكان الفرع غلط» report, written by the server
 * (the app can only notify `supervisor_<company>` or one uid, and the
 * `supervisor_<company>` broadcast also reaches delegates with position
 * supervisor, who do not review these reports: user decision 28 Nov).
 *
 *   opened (new, or reopened after rejected / fixed) → the company's
 *     supervisors (staff accounts, company admin roles);
 *   open → forwarded → the chain admins (super admins when the chain has
 *     none) and the delegate;
 *   → rejected / fixed → the delegate.
 *
 * One notification document per recipient (delegateUid = that uid), so the
 * inbox and onNotificationCreated's push work as for any personal alert.
 * Ids carry the trigger's event id, so a retried event writes nothing new.
 */
type Doc = Record<string, unknown> | null | undefined;

export type ReportEvent = "opened" | "forwarded" | "rejected" | "fixed";

export type Audience = "company_supervisors" | "chain_admins" | "delegate";

/** Same spellings as companyAdminRoles() in firestore.rules. */
export const COMPANY_SUPERVISOR_ROLES = [
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
];

/** Same spellings as orgAdminRoleList() in firestore.rules. */
export const CHAIN_ADMIN_ROLES = [
  "organization-admin", "organization_admin", "organizationadmin", "organizationAdmin", "org-admin",
];

/** Same spellings as superAdminRoleList() in firestore.rules. */
export const SUPER_ADMIN_ROLES = [
  "super-admin", "super_admin", "superadmin", "superAdmin", "Super-Admin", "SUPER_ADMIN",
];

/** Cap on staff recipients of one event (a chain or company has a few). */
export const MAX_STAFF_RECIPIENTS = 30;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** The event this write is, or null when nobody needs to hear about it. */
export function reportEvent(before: Doc, after: Doc): ReportEvent | null {
  if (!after) return null;
  const from = before ? str(before.status) : "";
  const to = str(after.status);
  if (to === from) return null;
  if (to === "open") return "opened";
  if (to === "forwarded" && from === "open") return "forwarded";
  if (to === "rejected" && (from === "open" || from === "forwarded")) return "rejected";
  if (to === "fixed" && from === "forwarded") return "fixed";
  return null;
}

/** Who is told about [event]. */
export function audiencesFor(event: ReportEvent): Audience[] {
  switch (event) {
  case "opened": return ["company_supervisors"];
  case "forwarded": return ["chain_admins", "delegate"];
  case "rejected":
  case "fixed": return ["delegate"];
  }
}

const INACTIVE = new Set(["suspended", "rejected", "deleted", "inactive", "disabled"]);

/** Active staff uids among [users] whose role is one of [roles]. */
export function activeStaffUids(
  users: Array<{uid: string; role?: unknown; status?: unknown; isActive?: unknown}>,
  roles: readonly string[],
): string[] {
  const out = new Set<string>();
  for (const u of users) {
    if (!u.uid) continue;
    if (!roles.includes(str(u.role))) continue;
    if (INACTIVE.has(str(u.status).toLowerCase()) || u.isActive === false) continue;
    out.add(u.uid);
  }
  return Array.from(out).sort().slice(0, MAX_STAFF_RECIPIENTS);
}

function branchLabel(a: Record<string, unknown>): string {
  return str(a.branchName) || "الفرع";
}

/** Title and body of the notification to [audience] for [event]. */
export function textFor(event: ReportEvent, audience: Audience, a: Record<string, unknown>):
  {title: string; body: string} {
  const branch = branchLabel(a);
  const who = str(a.delegateName) || "مندوب";
  if (audience === "company_supervisors") {
    return {
      title: "بلاغ «مكان الفرع غلط»",
      body: `${who} بيقول إن مكان ${branch} على السيستم غلط. افتح «بلاغات أماكن الفروع» وراجع الموقع.`,
    };
  }
  if (audience === "chain_admins") {
    return {
      title: "فرع محتاج تصحيح مكانه",
      body: `مشرف الشركة حوّل بلاغ عن مكان ${branch}. عدّل الفرع من شاشة الفروع، وبعدين اقفل البلاغ.`,
    };
  }
  switch (event) {
  case "forwarded":
    return {
      title: "بلاغك عن مكان الفرع اتحوّل للتصحيح",
      body: `المشرف وافق على بلاغك عن ${branch}، واتبعت للي بيعدّل الفروع.`,
    };
  case "fixed":
    return {
      title: "مكان الفرع اتصحح",
      body: `مكان ${branch} اتعدّل. جرّب تسجّل حضورك تاني.`,
    };
  case "rejected": {
    const reason = str(a.rejectReason);
    return {
      title: "بلاغك عن مكان الفرع اترفض",
      body: reason ? `البلاغ عن ${branch} اترفض: ${reason}` : `البلاغ عن ${branch} اترفض.`,
    };
  }
  default:
    return {title: "بلاغ عن مكان الفرع", body: branch};
  }
}

/** The notification documents for one recipient list. */
export function notificationsFor(
  event: ReportEvent,
  audience: Audience,
  reportId: string,
  eventId: string,
  after: Record<string, unknown>,
  recipientUids: string[],
): Array<{id: string; doc: Record<string, unknown>}> {
  const org = str(after.organizationUID);
  const co = str(after.companyUID);
  const t = textFor(event, audience, after);
  const safeEvent = eventId.replace(/[^A-Za-z0-9_-]/g, "");
  return recipientUids.filter((u) => !!u).map((uid) => ({
    id: `blr_${reportId}_${safeEvent}_${uid}`.slice(0, 1400),
    doc: {
      delegateUid: uid,
      // Both spellings: the app reads organizationUID, onNotificationCreated
      // reads organizationId.
      ...(org ? {organizationUID: org, organizationId: org} : {}),
      ...(co ? {companyUID: co, companyId: co} : {}),
      title: t.title,
      body: t.body,
      type: "branch_location_report",
      reportId,
      reportStatus: str(after.status),
      branchId: str(after.branchId),
      isRead: false,
      createdBy: "system",
    },
  }));
}
