import {
  Period,
  formatCairoDayArabic,
  periodShortTitleArabic,
} from "./subscription_logic";

export const SUBSCRIPTION_REMINDER_TYPE = "subscription_renewal_reminder";
export const REMINDER_RUNS = "subscription_reminder_runs";

const COMPANY_SUPERVISOR_ROLES = new Set([
  "supervisor",
  "company_supervisor",
  "company-supervisor",
]);

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Resolved company key for scoping (companyUID or legacy companyId). */
export function companyKeyOfUser(u: Pick<SubscriptionInvoiceUserCandidate, "companyUID" | "companyId">): string {
  return str(u.companyUID) || str(u.companyId);
}

function companyOf(u: SubscriptionInvoiceUserCandidate): string {
  return companyKeyOfUser(u);
}

function isCompanySupervisorRole(role: unknown): boolean {
  const raw = str(role).toLowerCase().replace(/_/g, "-");
  return COMPANY_SUPERVISOR_ROLES.has(str(role)) || COMPANY_SUPERVISOR_ROLES.has(raw);
}

/** Matches app staff inactive semantics (storage upload / task notify). */
export function isExcludedSupervisorRecipient(u: SubscriptionInvoiceUserCandidate): boolean {
  if (u.isActive === false) return true;
  const s = str(u.status).toLowerCase().replace(/-/g, "_");
  return s === "inactive" || s === "disabled" || s === "suspended" || s === "deleted"
    || s === "pending" || s === "rejected";
}

/** Inbox fallback when no live supervisor user exists (matches leave / rules). */
export function supervisorCompanyInboxKey(companyUID: string): string {
  const company = str(companyUID);
  return company ? `supervisor_${company}` : "";
}

export interface SubscriptionInvoiceUserCandidate {
  uid: string;
  role?: unknown;
  companyUID?: unknown;
  companyId?: unknown;
  organizationUID?: unknown;
  organizationId?: unknown;
  isActive?: unknown;
  status?: unknown;
}

/** Uncovered app-added delegates grouped for one reminder per company per day. */
export interface UncoveredCompanyReminderGroup {
  companyUID: string;
  /** First non-empty org on a request in this company group (notification payload). */
  organizationUID: string;
  organizationUIDs: string[];
  /** True when requests under the same company reference more than one org. */
  orgConflict: boolean;
  count: number;
}

function finalizeCompanyGroup(g: {
  companyUID: string;
  organizationUID: string;
  orgs: Set<string>;
  count: number;
}): UncoveredCompanyReminderGroup {
  const organizationUIDs = [...g.orgs].filter(Boolean).sort((a, b) => a.localeCompare(b));
  const organizationUID = organizationUIDs[0] || g.organizationUID;
  return {
    companyUID: g.companyUID,
    organizationUID,
    organizationUIDs,
    orgConflict: organizationUIDs.length > 1,
    count: g.count,
  };
}

/**
 * Groups uncovered delegates by company only (tenant). Mixed or missing
 * `organizationUID` on requests must not fan out multiple reminders.
 */
export function groupUncoveredDelegatesByCompany(
  entries: Iterable<{companyUID: unknown; organizationUID?: unknown; organizationId?: unknown}>,
): Map<string, UncoveredCompanyReminderGroup> {
  const internal = new Map<string, {
    companyUID: string;
    organizationUID: string;
    orgs: Set<string>;
    count: number;
  }>();
  for (const e of entries) {
    const companyUID = str(e.companyUID);
    if (!companyUID) continue;
    const organizationUID = str(e.organizationUID) || str(e.organizationId);
    const g = internal.get(companyUID);
    if (g) {
      g.count++;
      if (organizationUID) g.orgs.add(organizationUID);
      if (!g.organizationUID && organizationUID) g.organizationUID = organizationUID;
    } else {
      const orgs = new Set<string>();
      if (organizationUID) orgs.add(organizationUID);
      internal.set(companyUID, {companyUID, organizationUID, orgs, count: 1});
    }
  }
  const groups = new Map<string, UncoveredCompanyReminderGroup>();
  for (const g of internal.values()) {
    groups.set(g.companyUID, finalizeCompanyGroup(g));
  }
  return groups;
}

function liveCompanySupervisors(opts: {
  companyUID: string;
  candidates: SubscriptionInvoiceUserCandidate[];
}): string[] {
  const company = str(opts.companyUID);
  if (!company) return [];
  const uids = new Set<string>();
  for (const u of opts.candidates) {
    if (isExcludedSupervisorRecipient(u)) continue;
    if (!isCompanySupervisorRole(u.role)) continue;
    if (companyOf(u) !== company) continue;
    const uid = str(u.uid);
    if (uid) uids.add(uid);
  }
  return [...uids].sort((a, b) => a.localeCompare(b));
}

/**
 * Renewal reminder recipients: every live company supervisor (personal inbox),
 * not `delegate_requests.supervisorUid`. With no live supervisor, the company
 * broadcast key `supervisor_{companyUID}` (all supervisors query this inbox).
 */
export function recipientUidsForSubscriptionReminder(opts: {
  companyUID: string;
  organizationUID?: string;
  candidates: SubscriptionInvoiceUserCandidate[];
}): string[] {
  const live = liveCompanySupervisors({companyUID: opts.companyUID, candidates: opts.candidates});
  if (live.length) return live;
  const fallback = supervisorCompanyInboxKey(opts.companyUID);
  return fallback ? [fallback] : [];
}

/** @deprecated Use recipientUidsForSubscriptionReminder */
export function userIdForSubscriptionInvoice(opts: {
  companyUID: string;
  organizationUID?: string;
  candidates: SubscriptionInvoiceUserCandidate[];
}): string {
  const all = recipientUidsForSubscriptionReminder(opts);
  return all[0] || "";
}

export function subscriptionReminderAlertDoc(opts: {
  recipientUid: string;
  organizationUID: string;
  companyUID: string;
  endingPeriod: Period;
  nextPeriod: Period;
  uncoveredCount: number;
  reminderDays: number;
}): Record<string, unknown> {
  const n = Math.max(1, opts.uncoveredCount);
  const delegateWord = n === 1 ? "مندوب واحد" : `${n} مناديب`;
  const endingTitle = periodShortTitleArabic(opts.endingPeriod);
  const nextTitle = periodShortTitleArabic(opts.nextPeriod);
  const endAr = formatCairoDayArabic(opts.endingPeriod.endDay);
  return {
    delegateUid: opts.recipientUid,
    title: "تذكير بتجديد اشتراك المناديب",
    body:
      `تنتهي فترة ${endingTitle} في ${endAr}. ` +
      `لديك ${delegateWord} مضاف${n === 1 ? "" : "ون"} من التطبيق بحاجة لتجديد اشتراك ${nextTitle} ` +
      `قبل انتهاء المهلة (خلال ${opts.reminderDays} يوماً من اليوم).`,
    type: SUBSCRIPTION_REMINDER_TYPE,
    companyUID: opts.companyUID,
    organizationId: opts.organizationUID,
    organizationUID: opts.organizationUID,
    periodCode: opts.nextPeriod.code,
    endingPeriodCode: opts.endingPeriod.code,
    uncoveredDelegateCount: n,
    isRead: false,
    senderName: "Tashil",
    senderRole: "system",
  };
}
