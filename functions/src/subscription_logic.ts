/**
 * Pure subscription rules (no Firestore). Mirrors
 * lib/core/utils/subscription_cycle_helper.dart; both must agree.
 *
 * - Periods: H1 = 1 Jan..30 Jun, H2 = 1 Jul..31 Dec, in Africa/Cairo time.
 * - Fee: 500 EGP per delegate per period, prorated by remaining months
 *   (the join month counts in full): 500 * remaining / 6, rounded to 2 dp.
 * - Free promotion: everything up to and including 2026-12-31 (Cairo) is free.
 * - One subscription per delegate covers all chains (add_organization is free).
 */

export const TIME_ZONE = "Africa/Cairo";
export const PERIOD_FEE_EGP = 500;
export const MONTHS_PER_PERIOD = 6;
/** Mohamed policy (PR #212): max delegates per single renewal / Paymob payment. */
export const MAX_DELEGATES_PER_RENEWAL = 100;
/** Last free day (inclusive), Cairo calendar date. */
export const FREE_PROMOTION_LAST_DAY = "2026-12-31";

export const REQUEST_TYPE_NEW = "new_delegate";
export const REQUEST_TYPE_RENEWAL = "renewal";
export const REQUEST_TYPE_ADD_ORG = "add_organization";

export type PaymentStatus = "pending" | "paid" | "failed" | "waived" | "not_required";

export interface CairoDate {
  year: number;
  month: number; // 1..12
  day: number;
}

const cairoFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  hourCycle: "h23",
});

function parts(at: Date): Record<string, number> {
  const out: Record<string, number> = {};
  for (const p of cairoFormatter.formatToParts(at)) {
    if (p.type !== "literal") out[p.type] = Number(p.value);
  }
  return out;
}

/** Calendar date of an instant in Cairo. */
export function cairoDate(at: Date): CairoDate {
  const p = parts(at);
  return {year: p.year, month: p.month, day: p.day};
}

export function isoDay(d: CairoDate): string {
  const mm = String(d.month).padStart(2, "0");
  const dd = String(d.day).padStart(2, "0");
  return `${d.year}-${mm}-${dd}`;
}

/** UTC instant of 00:00 Cairo time on the given calendar day (DST-aware). */
export function cairoMidnight(year: number, month: number, day: number): Date {
  // Cairo is UTC+2 or UTC+3 (summer time). Try both, keep the one that lands on 00:00.
  for (const offsetHours of [2, 3]) {
    const guess = new Date(Date.UTC(year, month - 1, day, -offsetHours));
    const p = parts(guess);
    if (p.year === year && p.month === month && p.day === day && p.hour === 0) return guess;
  }
  return new Date(Date.UTC(year, month - 1, day, -2));
}

export interface Period {
  code: string; // e.g. 2027_H1
  year: number;
  half: 1 | 2;
  /** Inclusive Cairo calendar days. */
  startDay: string;
  endDay: string;
  /** UTC instants: start = 00:00 Cairo on the first day; endsAt = 00:00 Cairo on the next period's first day. */
  startsAt: Date;
  endsAt: Date;
}

export function periodFor(year: number, half: 1 | 2): Period {
  const startMonth = half === 1 ? 1 : 7;
  const next = half === 1 ? {y: year, m: 7} : {y: year + 1, m: 1};
  return {
    code: `${year}_H${half}`,
    year,
    half,
    startDay: isoDay({year, month: startMonth, day: 1}),
    endDay: half === 1 ? `${year}-06-30` : `${year}-12-31`,
    startsAt: cairoMidnight(year, startMonth, 1),
    endsAt: cairoMidnight(next.y, next.m, 1),
  };
}

export function periodOf(at: Date): Period {
  const d = cairoDate(at);
  return periodFor(d.year, d.month <= 6 ? 1 : 2);
}

export function parsePeriodCode(code: unknown): Period | null {
  if (typeof code !== "string") return null;
  const m = /^(\d{4})_H([12])$/.exec(code.trim());
  if (!m) return null;
  return periodFor(Number(m[1]), Number(m[2]) as 1 | 2);
}

/** Months left in the period including the current month (1..6). */
export function remainingMonths(at: Date): number {
  const {month} = cairoDate(at);
  return MONTHS_PER_PERIOD - ((month - 1) % MONTHS_PER_PERIOD);
}

/** The single rounding rule: half-up to 2 decimals. */
export function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function feeForMonths(months: number): number {
  const m = Math.max(1, Math.min(MONTHS_PER_PERIOD, Math.trunc(months)));
  return roundMoney((PERIOD_FEE_EGP * m) / MONTHS_PER_PERIOD);
}

/**
 * Optional quote context. The free-period bypass is honored ONLY when
 * `projectId` is exactly "tashil-dev". The same company flag or config
 * list on practice-firebase-72df1 (prod) is ignored.
 */
export interface QuoteOptions {
  projectId?: string;
  companyUID?: string;
  bypassCompanyUIDs?: string[];
  companyFreePeriodEnded?: boolean;
}

const TASHIL_DEV_PROJECT = "tashil-dev";

export function shouldBypassFreePeriod(opts?: QuoteOptions): boolean {
  if (!opts) return false;
  if ((opts.projectId || "").trim() !== TASHIL_DEV_PROJECT) return false;
  const company = (opts.companyUID || "").trim();
  if (!company) return false;
  if (opts.companyFreePeriodEnded === true) return true;
  return (opts.bypassCompanyUIDs || []).some((id) => (id || "").trim() === company);
}

export function isFreePromotion(at: Date, opts?: QuoteOptions): boolean {
  if (shouldBypassFreePeriod(opts)) return false;
  return isoDay(cairoDate(at)) <= FREE_PROMOTION_LAST_DAY;
}

/** Fee one delegate pays when subscribing or renewing at `at`. */
export function feeAt(at: Date, opts?: QuoteOptions): number {
  return isFreePromotion(at, opts) ? 0 : feeForMonths(remainingMonths(at));
}

export function toCents(amount: number): number {
  return Math.round(roundMoney(amount) * 100);
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/**
 * A delegate is "app-added" when it was created by an approved mobile
 * new_delegate request: the delegate uid is the request doc id. Angular/web
 * delegates never have such a request, so they are never suspended.
 */
export function isAppAddedRegistration(requestId: string, data: Record<string, unknown>): boolean {
  return (
    str(data.requestType || REQUEST_TYPE_NEW) === REQUEST_TYPE_NEW &&
    str(data.status) === "approved" &&
    str(data.supervisorUid) !== "" &&
    str(data.existingDelegateUid) === "" &&
    requestId.trim() !== ""
  );
}

/** Delegate uids a request pays for (new_delegate: itself; renewal: the selected list). */
export function coveredUids(requestId: string, data: Record<string, unknown>): string[] {
  const type = str(data.requestType || REQUEST_TYPE_NEW);
  if (type === REQUEST_TYPE_NEW) return [requestId];
  if (type === REQUEST_TYPE_RENEWAL && Array.isArray(data.coveredDelegateUids)) {
    return [...new Set(data.coveredDelegateUids.map(str).filter((u) => u !== ""))];
  }
  return [];
}

/** A paid (or, for free periods, waived) request covers its delegates for its period. */
export function requestCoversPeriod(data: Record<string, unknown>, periodCode: string): boolean {
  if (str(data.periodCode) !== periodCode) return false;
  const status = str(data.paymentStatus);
  if (status === "paid") return true;
  const period = parsePeriodCode(periodCode);
  return status === "waived" && period !== null && period.endDay <= FREE_PROMOTION_LAST_DAY;
}

/** Statuses the period-end job moves to "suspended". */
export function shouldSuspendStatus(status: unknown): boolean {
  const s = str(status).toLowerCase();
  return s === "active" || s === "approved";
}

export const SUSPEND_REASON = "subscription_expired";

export interface QuoteItem {
  uid: string;
  fee: number;
}

export interface Quote {
  periodCode: string;
  remainingMonths: number;
  items: QuoteItem[];
  amount: number;
  amountCents: number;
}

/** Authoritative amount for a payable request at `at` (sum of per-delegate prorated fees). */
export function quoteFor(uids: string[], at: Date, opts?: QuoteOptions): Quote {
  const fee = feeAt(at, opts);
  const items = uids.map((uid) => ({uid, fee}));
  const amount = roundMoney(items.reduce((s, i) => s + i.fee, 0));
  return {
    periodCode: periodOf(at).code,
    remainingMonths: remainingMonths(at),
    items,
    amount,
    amountCents: toCents(amount),
  };
}
