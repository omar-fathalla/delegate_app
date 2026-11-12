import {
  Period,
  formatCairoDayArabic,
  periodShortTitleArabic,
} from "./subscription_logic";

export const SUBSCRIPTION_REMINDER_TYPE = "subscription_renewal_reminder";
export const REMINDER_RUNS = "subscription_reminder_runs";

export function subscriptionReminderAlertDoc(opts: {
  supervisorUid: string;
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
    delegateUid: opts.supervisorUid,
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
