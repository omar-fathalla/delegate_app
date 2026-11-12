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

function companyOf(u: SubscriptionInvoiceUserCandidate): string {
  return str(u.companyUID) || str(u.companyId);
}

function orgOf(u: SubscriptionInvoiceUserCandidate): string {
  return str(u.organizationUID) || str(u.organizationId);
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

/**
 * Recipient for subscription renewal invoice / reminder: current company
 * supervisor inbox, not the staff uid on `delegate_requests.supervisorUid`.
 * When several live supervisors exist, pick the lowest uid (localeCompare).
 */
export function userIdForSubscriptionInvoice(opts: {
  companyUID: string;
  organizationUID?: string;
  candidates: SubscriptionInvoiceUserCandidate[];
}): string {
  const company = str(opts.companyUID);
  if (!company) return "";
  const org = str(opts.organizationUID);
  const matches = opts.candidates.filter((u) => {
    if (isExcludedSupervisorRecipient(u)) return false;
    if (!isCompanySupervisorRole(u.role)) return false;
    if (companyOf(u) !== company) return false;
    if (!org) return true;
    const uOrg = orgOf(u);
    return !uOrg || uOrg === org;
  });
  if (matches.length) {
    matches.sort((a, b) => str(a.uid).localeCompare(str(b.uid)));
    return str(matches[0].uid);
  }
  return supervisorCompanyInboxKey(company);
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
