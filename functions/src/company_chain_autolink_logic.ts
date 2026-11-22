/**
 * Pure logic for automatic chain links (Mohamed, 17 Nov 2026).
 *
 * A link is the same per-chain doc app 1.14.3 already reads:
 * organizations/{org}/companies/{co}/delegates/{uid}. Auto-created copies
 * carry autoLinked=true. Nothing is ever deleted here.
 *
 * Free chains (فتح الله, the legacy web system; configurable through
 * config/subscriptions.freeChainOrgUids or organizations/{org}.subscriptionExempt)
 * need no payment. Every other chain needs paid coverage:
 * - active + paid  -> linked to every company chain, free ones included;
 * - active, unpaid -> linked to free chains only;
 * - expired        -> suspendExpiredSubscriptions suspends the paid-chain
 *                     copies only (never the free-chain copy); renewal
 *                     reactivates them and the next reconcile links any
 *                     chain the company joined meanwhile.
 * Becoming active never unlocks a paid chain by itself; only coverage does.
 */

export type Data = Record<string, unknown>;

export interface DelegateCopy {
  orgId: string;
  data: Data;
}

export interface ChainInfo {
  id: string;
  name: string;
}

export interface Coverage {
  /** Free promotion (config/subscriptions freePromotionLastDay) is on. */
  free: boolean;
  /** Current period code, e.g. 2027-H1. */
  periodCode: string;
  /** Uids a paid/waived delegate_request covers for the current period. */
  covered: Set<string>;
  /** Grace days after a period end: last period's coverage still counts. */
  inGrace: boolean;
  previousPeriodCode: string;
  previousCovered: Set<string>;
  /** Chains that need no payment (فتح الله). */
  freeChains: Set<string>;
  /** Evaluation instant; enables the legacy `endDate` expiry check. */
  now?: Date;
}

/** Free chains from config/subscriptions.freeChainOrgUids and org flags. */
export function freeChainIds(
  config: Data | null,
  orgs: Array<{id: string; data: Data}>,
): Set<string> {
  const out = new Set<string>();
  const list = config?.freeChainOrgUids;
  if (Array.isArray(list)) for (const v of list) if (str(v)) out.add(str(v));
  for (const o of orgs) if (o.data.subscriptionExempt === true) out.add(o.id);
  return out;
}

export function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Fields copied from the delegate's own chain doc into a new chain doc. */
export const AUTO_LINK_COPY_FIELDS = [
  "uid", "delegatePublicId", "firstName", "secondName", "thirdName", "fullName",
  "phoneNumber", "nationalId", "nationalityID", "city", "birthDate", "gender",
  "companyUID", "companyName", "profileImageUrl", "personalPhotoUrl",
  "nationalIdFrontUrl", "nationalIdBackUrl", "documents", "status", "role",
  "isDeductedFromCompany", "receiptCode", "subscription", "nextSubscription",
  "originOrganizationName", "registeredVia", "approvedRequestId", "email",
  "holds", "statusReason",
] as const;

/** Legacy (app 1.14.x) payment methods meaning "free promotion" (= waived). */
export const LEGACY_FREE_PROMOTION_METHODS = new Set(["freePromotion", "free_promotion"]);

/**
 * A paid (or waived-in-its-period) subscription mirror for [periodCode].
 * Mirrors SubscriptionCycleHelper._mapCoversPeriod (Dart); both must agree.
 *
 * Period: `periodCode`, else the legacy `cycle`.
 * - New shape (non-empty `paymentStatus`): unchanged. `paid` covers,
 *   `waived` covers only when [free]; anything else does not.
 * - Legacy 1.14.x shape (no `paymentStatus`; every map on prod as of Nov
 *   2026): a free-promotion `paymentMethod` behaves like `waived`; otherwise
 *   `isPaid === true` behaves like `paid`. When [now] is given, a legacy
 *   `endDate` before it (zone-less strings are Cairo wall time) means expired.
 */
export function mapCoversPeriod(sub: unknown, periodCode: string, free: boolean, now?: Date): boolean {
  if (!sub || typeof sub !== "object") return false;
  const m = sub as Data;
  const period = str(m.periodCode) || str(m.cycle);
  if (!period || period !== periodCode) return false;
  const status = str(m.paymentStatus);
  if (status) {
    if (status === "paid") return true;
    return status === "waived" && free;
  }
  if (now && legacyEndDatePassed(m.endDate, now)) return false;
  if (LEGACY_FREE_PROMOTION_METHODS.has(str(m.paymentMethod))) return free;
  return m.isPaid === true;
}

/** Cairo is UTC+2 in winter, UTC+3 in summer: offset (hours) at [at]. */
function cairoOffsetHours(at: Date): number {
  const p = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  }).formatToParts(at);
  const g = (t: string) => Number(p.find((x) => x.type === t)?.value);
  const wall = Date.UTC(g("year"), g("month") - 1, g("day"), g("hour") % 24, g("minute"));
  return Math.round((wall - at.getTime()) / 3600000);
}

/** Legacy `endDate` (ISO string, Date, or Timestamp) is before [now]. Unparseable -> false. */
export function legacyEndDatePassed(raw: unknown, now: Date): boolean {
  let end: Date | null = null;
  if (raw instanceof Date) {
    end = raw;
  } else if (typeof raw === "string" && raw.trim()) {
    const s = raw.trim();
    const zoned = /([zZ]|[+-]\d{2}:?\d{2})$/.test(s);
    const parsed = new Date(zoned ? s : `${s}Z`);
    if (!Number.isNaN(parsed.getTime())) {
      // Zone-less: Cairo wall time -> shift by the Cairo offset at that moment.
      end = zoned ? parsed : new Date(parsed.getTime() - cairoOffsetHours(parsed) * 3600000);
    }
  } else if (raw && typeof raw === "object" && typeof (raw as {toDate?: unknown}).toDate === "function") {
    const d = (raw as {toDate: () => Date}).toDate();
    if (d instanceof Date) end = d;
  }
  if (!end || Number.isNaN(end.getTime())) return false;
  return now.getTime() > end.getTime();
}

/** Paid coverage now: server requests first, the doc mirror as a fallback. */
export function isCovered(uid: string, copies: DelegateCopy[], cov: Coverage): boolean {
  if (cov.free) return true;
  if (cov.covered.has(uid)) return true;
  if (cov.inGrace && cov.previousCovered.has(uid)) return true;
  for (const c of copies) {
    if (mapCoversPeriod(c.data.subscription, cov.periodCode, cov.free, cov.now)) return true;
    if (mapCoversPeriod(c.data.nextSubscription, cov.periodCode, cov.free, cov.now)) return true;
    // Grace: last period's map still counts, so its endDate is not applied.
    if (cov.inGrace && mapCoversPeriod(c.data.subscription, cov.previousPeriodCode, cov.free)) {
      return true;
    }
  }
  return false;
}

export type Ineligible =
  | "no_active_copy"
  | "suspended_copy"
  | "user_suspended"
  | "not_paid";

const isActive = (d: Data) => ["active", "approved"].includes(str(d.status).toLowerCase());
const isBlocked = (d: Data) => ["suspended", "rejected"].includes(str(d.status).toLowerCase());

/**
 * Which kinds of chain the delegate may be linked to.
 * - free: an active copy somewhere, login not suspended, no suspended
 *   free-chain copy.
 * - paid: the same, plus paid coverage now and no suspended paid-chain copy.
 * Pending copies (awaiting approval) are ignored.
 */
export function linkRights(
  uid: string,
  copies: DelegateCopy[],
  user: Data | null,
  cov: Coverage,
): {free: boolean; paid: boolean; reason?: Ineligible} {
  if (!copies.some((c) => isActive(c.data))) return {free: false, paid: false, reason: "no_active_copy"};
  if (user && str(user.status).toLowerCase() === "suspended") {
    return {free: false, paid: false, reason: "user_suspended"};
  }
  const freeBlocked = copies.some((c) => cov.freeChains.has(c.orgId) && isBlocked(c.data));
  const paidBlocked = copies.some((c) => !cov.freeChains.has(c.orgId) && isBlocked(c.data));
  const paidCopies = copies.filter((c) => !cov.freeChains.has(c.orgId));
  const covered = isCovered(uid, paidCopies.length ? paidCopies : copies, cov);
  const paid = !paidBlocked && covered;
  return {
    free: !freeBlocked,
    paid,
    reason: paid ? undefined : (paidBlocked ? "suspended_copy" : "not_paid"),
  };
}

/** Kept for callers that only need a yes/no for paid chains. */
export function eligibility(
  uid: string,
  copies: DelegateCopy[],
  user: Data | null,
  cov: Coverage,
): {ok: true} | {ok: false; reason: Ineligible} {
  const r = linkRights(uid, copies, user, cov);
  return r.paid ? {ok: true} : {ok: false, reason: r.reason || "not_paid"};
}

/**
 * The `position` to store: only the role ("Promoter" / "Supervisor"), never
 * chain names (TAS-232 / TAS-234). Chains live in `allOrganizationNames`,
 * `originOrganizationName` and `isExternal`. A legacy value such as
 * "Promoter (جملة ماركت + 9 سلاسل)" is cleaned back to "Promoter", and an
 * existing "Supervisor" stays "Supervisor".
 */
export function plainPosition(raw: unknown): string {
  const s = str(raw).replace(/\s*\(.*\)\s*$/s, "").trim();
  return s !== "" ? s : "Promoter";
}

/** The copy to clone: an active, non-auto-linked copy, newest first. */
export function pickSource(copies: DelegateCopy[]): DelegateCopy | null {
  const active = copies.filter((c) => {
    const s = str(c.data.status).toLowerCase();
    return s === "active" || s === "approved";
  });
  const own = active.filter((c) => c.data.autoLinked !== true);
  const pool = own.length ? own : active;
  return pool[0] ?? null;
}

export interface DelegatePlan {
  uid: string;
  /** May be linked to paid chains. */
  eligible: boolean;
  /** May be linked to free chains. */
  freeEligible: boolean;
  reason?: Ineligible;
  /** Chains to create a copy in. */
  create: string[];
  /** All chain names the delegate will be on after the plan. */
  allNames: string[];
}

export function planDelegate(
  uid: string,
  copies: DelegateCopy[],
  user: Data | null,
  chains: ChainInfo[],
  cov: Coverage,
): DelegatePlan {
  const have = new Set(copies.map((c) => c.orgId));
  const nameOf = new Map(chains.map((c) => [c.id, c.name]));
  const r = linkRights(uid, copies, user, cov);
  const create = chains
    .filter((c) => !have.has(c.id))
    .filter((c) => (cov.freeChains.has(c.id) ? r.free : r.paid))
    .map((c) => c.id);
  const ids = [...have, ...create];
  const allNames = [...new Set(ids.map((id) => {
    const copy = copies.find((c) => c.orgId === id);
    return (nameOf.get(id) || str(copy?.data.organizationName) || "").trim();
  }).filter((n) => n !== ""))];
  return {uid, eligible: r.paid, freeEligible: r.free, reason: r.reason, create, allNames};
}

/** The new chain doc, cloned from [source] with the chain fields set. */
export function buildAutoLinkedCopy(opts: {
  source: DelegateCopy;
  chain: ChainInfo;
  allNames: string[];
}): Data {
  const src = opts.source.data;
  const out: Data = {};
  for (const k of AUTO_LINK_COPY_FIELDS) {
    if (src[k] !== undefined) out[k] = src[k];
  }
  const origin = str(src.originOrganizationName) || str(src.organizationName);
  out.organizationUID = opts.chain.id;
  out.organizationName = opts.chain.name;
  out.originOrganizationName = origin;
  out.isExternal = origin.toLowerCase() !== opts.chain.name.toLowerCase();
  out.position = plainPosition(src.position);
  if (opts.allNames.length > 1) out.allOrganizationNames = opts.allNames;
  out.autoLinked = true;
  out.autoLinkedFromOrganizationUID = opts.source.orgId;
  out.autoLinkReason = "company_chain";
  return out;
}

/** True when a delegate doc write should start a reconcile. */
export function delegateWriteNeedsReconcile(before: Data | null, after: Data | null): boolean {
  if (!after) return false; // deletes never add links
  if (!before) return after.autoLinked !== true; // our own creates are skipped
  const s = (d: Data) => str(d.status).toLowerCase();
  const becameActive = s(after) !== s(before) && (s(after) === "active" || s(after) === "approved");
  const sub = (d: Data) => JSON.stringify([d.subscription ?? null, d.nextSubscription ?? null]);
  const companyChanged = str(after.companyUID) !== str(before.companyUID);
  return becameActive || companyChanged || sub(after) !== sub(before);
}

export function chunks<T>(list: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

/**
 * users/{uid} change for the expiry job, or null for no write.
 * suspend: only an active login with no active free-chain copy.
 * reactivate: only a login suspended with reason subscription_expired.
 * statusReason null means "delete the field".
 */
export function mirrorUserStatusPlan(opts: {
  op: "suspend" | "reactivate";
  user: Data;
  hasActiveFreeChainCopy: boolean;
}): {status: string; statusReason: string | null} | null {
  const status = str(opts.user.status).toLowerCase();
  const reason = str(opts.user.statusReason);
  if (opts.op === "suspend") {
    if (opts.hasActiveFreeChainCopy) return null;
    if (status !== "" && status !== "active" && status !== "approved") return null;
    return {status: "suspended", statusReason: "subscription_expired"};
  }
  if (status === "suspended" && reason === "subscription_expired") {
    return {status: "active", statusReason: null};
  }
  return null;
}
