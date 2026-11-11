import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  PaymentStatus,
  Period,
  Quote,
  QuoteOptions,
  REQUEST_TYPE_NEW,
  REQUEST_TYPE_RENEWAL,
  coveredUids,
  isAppAddedRegistration,
  isFreePromotion,
  isRenewalCoverageExpired,
  parsePeriodCode,
  parseAdvanceRenewalConfig,
  periodOf,
  quoteFor,
  resolvePayablePeriod,
  toCents,
  requestCoversPeriod,
  MAX_DELEGATES_PER_RENEWAL,
  type AdvanceRenewalConfig,
} from "./subscription_logic";
import {M1_SOURCE, M2_SOURCE, planExpiryHoldWrite, shouldShadowReactivateAfterExpiryClear} from "./subscription_holds";

type Db = admin.firestore.Firestore;
type Data = Record<string, unknown>;

const REQUESTS = "delegate_requests";
const RUNS = "subscription_suspension_runs";
const EVENTS = "subscription_payment_events";
const COVERAGE = "subscription_coverage";
const SUPER_ADMIN_ROLE = "super-admin";
const BATCH_LIMIT = 400;
const IN_LIMIT = 30;

function chunks<T>(list: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Attach timestamps and turn a null statusReason into a delete (authoritative). */
function withWriteMeta(update: Data, ts: FirebaseFirestore.FieldValue): Data {
  const out: Data = {...update, updatedAt: ts};
  if (out.statusReason === null) out.statusReason = FieldValue.delete();
  return out;
}

/** Batched writer that commits every BATCH_LIMIT operations. */
class Batcher {
  private batch: admin.firestore.WriteBatch;
  private count = 0;
  writes = 0;
  constructor(private db: Db) {
    this.batch = db.batch();
  }
  async update(ref: admin.firestore.DocumentReference, data: Data): Promise<void> {
    this.batch.update(ref, data as admin.firestore.UpdateData<admin.firestore.DocumentData>);
    this.count++;
    this.writes++;
    if (this.count >= BATCH_LIMIT) await this.flush();
  }
  async set(ref: admin.firestore.DocumentReference, data: Data): Promise<void> {
    this.batch.set(ref, data);
    this.count++;
    this.writes++;
    if (this.count >= BATCH_LIMIT) await this.flush();
  }
  async flush(): Promise<void> {
    if (this.count === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.count = 0;
  }
}

/** Uids of every delegate created by an approved app new_delegate request. */
export async function appAddedDelegateUids(db: Db): Promise<Map<string, Data>> {
  const snap = await db.collection(REQUESTS)
    .where("requestType", "==", REQUEST_TYPE_NEW)
    .where("status", "==", "approved")
    .get();
  const out = new Map<string, Data>();
  for (const doc of snap.docs) {
    if (isAppAddedRegistration(doc.id, doc.data())) out.set(doc.id, doc.data());
  }
  return out;
}

/** Uids paid (or waived, for a free period) for `period`. */
export async function coveredDelegateUids(db: Db, period: Period): Promise<Set<string>> {
  const snap = await db.collection(REQUESTS).where("periodCode", "==", period.code).get();
  const out = new Set<string>();
  for (const doc of snap.docs) {
    if (requestCoversPeriod(doc.data(), period.code)) {
      for (const uid of coveredUids(doc.id, doc.data())) out.add(uid);
    }
  }
  return out;
}

async function delegateDocsFor(db: Db, uids: string[]) {
  const docs: admin.firestore.QueryDocumentSnapshot[] = [];
  for (const part of chunks(uids, IN_LIMIT)) {
    const snap = await db.collectionGroup("delegates").where("uid", "in", part).get();
    docs.push(...snap.docs);
  }
  return docs;
}

export interface SuspensionResult {
  periodCode: string;
  skipped?: "free_promotion";
  appAdded: number;
  covered: number;
  candidates: number;
  suspendedDocs: number;
  suspendedUsers: number;
  alreadySuspended: number;
  /** Expiry holds removed because the uid is already covered for this period. */
  clearedHolds?: number;
}

/**
 * Adds a subscription_expired hold on every app-added delegate that has no
 * paid subscription for the current period, through holds.ts. Web delegates
 * are never selected. Holds stack: a manual / admin suspension is not
 * overwritten; the expiry hold is added beside it. Shadow mode (default)
 * does not write status, statusReason, or users/{uid}. Idempotent: an
 * existing expiry hold is left as it is. Do not deploy
 * suspendExpiredSubscriptions with this change.
 */
export async function runSubscriptionSuspension(db: Db, now: Date): Promise<SuspensionResult> {
  const period = periodOf(now);
  const base: SuspensionResult = {
    periodCode: period.code, appAdded: 0, covered: 0, candidates: 0,
    suspendedDocs: 0, suspendedUsers: 0, alreadySuspended: 0,
  };
  if (isFreePromotion(now)) {
    const res = {...base, skipped: "free_promotion" as const};
    console.log(JSON.stringify({event: "subscription_suspension", ...res}));
    return res;
  }
  const appAdded = await appAddedDelegateUids(db);
  const covered = await coveredDelegateUids(db, period);
  const candidates = [...appAdded.keys()].filter((uid) => !covered.has(uid));
  const res: SuspensionResult = {...base, appAdded: appAdded.size, covered: covered.size, candidates: candidates.length};
  const ts = FieldValue.serverTimestamp();
  const writer = new Batcher(db);
  const at = now.toISOString();
  const mode = process.env.HOLDS_AUTHORITY_MODE; // holdsMode() reads this

  for (const doc of await delegateDocsFor(db, candidates)) {
    const planned = planExpiryHoldWrite({
      data: (doc.data() || {}) as Data,
      op: "add",
      at,
      actor: "system",
      source: M1_SOURCE,
      periodCode: period.code,
      mode,
    });
    if (!planned.ok) continue;
    if (planned.unchanged) {
      res.alreadySuspended++;
      continue;
    }
    await writer.update(doc.ref, withWriteMeta({
      ...planned.update,
      "subscription.suspendedForPeriod": period.code,
      "subscription.suspendedAt": ts,
    }, ts));
    if (planned.plan.history && Object.keys(planned.plan.history).length) {
      await writer.set(doc.ref.collection("statusHistory").doc(), {
        ...planned.plan.history,
        writtenAt: ts,
      });
    }
    res.suspendedDocs++;
  }
  // Prepaid / already-covered app-added uids: drop a leftover expiry hold
  // (e.g. advance renewal paid in the previous period). Shadow mode still
  // does not write users/{uid}, but it does reactivate when no holds remain
  // (same as M2), unless a legacy non-expiry suspension is present.
  let clearedHolds = 0;
  const coveredList = [...covered];
  for (const doc of await delegateDocsFor(db, coveredList)) {
    const uid = str(doc.get("uid")) || doc.ref.id;
    if (!appAdded.has(uid)) continue;
    const planned = planExpiryHoldWrite({
      data: (doc.data() || {}) as Data,
      op: "remove",
      at,
      actor: "system",
      source: M1_SOURCE,
      periodCode: period.code,
      mode,
      inferLegacyExpiry: true,
    });
    const nextSub = doc.get("nextSubscription") as Data | undefined;
    const promote = nextSub && str(nextSub.periodCode) === period.code ? {
      subscription: nextSub,
      nextSubscription: FieldValue.delete(),
    } : {};
    if ((!planned.ok || planned.unchanged) && !Object.keys(promote).length) continue;
    const update: Data = {...(planned.ok && !planned.unchanged ? planned.update : {}), ...promote};
    // Shadow: same as M2 — a prepaid delegate must not stay suspended
    // after the expiry hold is cleared and the paid period is promoted.
    if (planned.ok && shouldShadowReactivateAfterExpiryClear(
      (doc.data() || {}) as Data,
      planned.plan.derivedStatus,
    )) {
      update.status = "active";
      update.statusReason = FieldValue.delete();
    }
    await writer.update(doc.ref, withWriteMeta(update, ts));
    if (planned.ok && !planned.unchanged && planned.plan.history && Object.keys(planned.plan.history).length) {
      await writer.set(doc.ref.collection("statusHistory").doc(), {
        ...planned.plan.history,
        writtenAt: ts,
      });
    }
    if (planned.ok && !planned.unchanged) clearedHolds++;
  }
  res.clearedHolds = clearedHolds;
  // users/{uid} is mirrored by the holds trigger once it is authoritative.
  // Shadow mode does not write it here.
  await writer.flush();
  await db.collection(RUNS).doc(`${period.code}_${now.toISOString().slice(0, 10)}`).set({
    ...res, ranAt: ts,
  }, {merge: true});
  console.log(JSON.stringify({event: "subscription_suspension", ...res}));
  return res;
}

export class QuoteError extends Error {
  constructor(public reason: string) {
    super(reason);
  }
}

/**
 * Authoritative amount for a payable request. Engineering's Paymob module
 * must call this when creating the Paymob order and charge exactly
 * `amountCents` (EGP piasters). Never trust an amount from the client.
 */
export async function quoteSubscriptionRequest(db: Db, requestId: string, at: Date): Promise<Quote> {
  const snap = await db.collection(REQUESTS).doc(requestId).get();
  if (!snap.exists) throw new QuoteError("not_found");
  const data = snap.data() as Data;
  const status = str(data.paymentStatus) as PaymentStatus;
  if (status === "paid") throw new QuoteError("already_paid");
  const requestStatus = str(data.status);
  if (requestStatus === "rejected" || requestStatus === "cancelled") throw new QuoteError("not_payable");
  if (status === "expired") throw new QuoteError("expired");
  if (status !== "pending" && status !== "failed") throw new QuoteError("not_payable");
  const type = str(data.requestType || REQUEST_TYPE_NEW);
  if (type !== REQUEST_TYPE_NEW && type !== REQUEST_TYPE_RENEWAL) throw new QuoteError("not_payable");
  const advanceCfg = await loadAdvanceRenewalConfig(db);
  const payable = resolvePayablePeriod(at, str(data.periodCode), advanceCfg);
  if (!payable) throw new QuoteError("period_mismatch");
  const uids = coveredUids(requestId, data);
  if (uids.length === 0) throw new QuoteError("no_delegates");
  if (uids.length > MAX_DELEGATES_PER_RENEWAL) throw new QuoteError("too_many_delegates");
  await assertCreatorScope(db, data);
  if (type === REQUEST_TYPE_RENEWAL) await assertRenewable(db, data, uids);
  const quoteOpts = await loadDevQuoteOptions(db, data);
  const quote = quoteFor(uids, at, {...quoteOpts, periodCode: payable.code});
  if (quote.amountCents <= 0) throw new QuoteError("free_period");
  await db.runTransaction(async (tx) => {
    await assertNotAlreadyCovered(tx, db, requestId, quote.periodCode, uids, at);
    await persistRecomputedQuote(tx, db, requestId, data, quote, at);
    claimCoverage(tx, db, requestId, quote.periodCode, uids, "pending");
  });
  return quote;
}

function projectIdOf(): string {
  const fromApp = admin.apps.length ? str(admin.app().options.projectId) : "";
  return fromApp || str(process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT);
}

/** Load tashil-dev-only free-period bypass flags. Never returns bypass data on prod. */
async function loadDevQuoteOptions(db: Db, data: Data): Promise<QuoteOptions> {
  const projectId = projectIdOf();
  const companyUID = str(data.companyUID);
  const opts: QuoteOptions = {projectId, companyUID};
  if (projectId !== "tashil-dev") return opts;
  const org = str(data.organizationUID);
  const [cfg, co] = await Promise.all([
    db.doc("config/subscription_dev").get(),
    companyUID && org
      ? db.doc(`organizations/${org}/companies/${companyUID}`).get()
      : Promise.resolve(null),
  ]);
  if (cfg.exists) {
    const list = cfg.get("bypassFreePeriodForCompanyUIDs");
    if (Array.isArray(list)) opts.bypassCompanyUIDs = list.map((v: unknown) => str(v)).filter(Boolean);
  }
  if (co && co.exists && co.get("subscriptionFreePeriodEnded") === true) {
    opts.companyFreePeriodEnded = true;
  }
  return opts;
}

async function loadAdvanceRenewalConfig(db: Db): Promise<AdvanceRenewalConfig> {
  const snap = await db.doc("config/subscriptions").get();
  return parseAdvanceRenewalConfig(snap.exists ? (snap.data() as Record<string, unknown>) : null);
}

/**
 * The request creator (users/{supervisorUid}) must belong to the request's
 * organization and company. Missing or empty companyUID is a denial.
 * Super-admin is exempt. This is the server-side counterpart of the
 * org-admin create rule (incomingOrgScoped + incomingCompanyScoped).
 */
export async function assertCreatorScope(db: Db, request: Data): Promise<void> {
  const creatorUid = str(request.supervisorUid);
  if (!creatorUid) throw new QuoteError("creator_missing");
  const snap = await db.collection("users").doc(creatorUid).get();
  if (!snap.exists) throw new QuoteError("creator_missing");
  const role = str(snap.get("role"));
  if (role === SUPER_ADMIN_ROLE) return;
  const creatorOrg = str(snap.get("organizationUID") || snap.get("organizationId"));
  const creatorCompany = str(snap.get("companyUID") || snap.get("companyId"));
  const requestOrg = str(request.organizationUID || request.organizationId);
  const requestCompany = str(request.companyUID || request.companyId);
  if (!creatorOrg || creatorOrg !== requestOrg) throw new QuoteError("creator_wrong_org");
  if (!creatorCompany || creatorCompany !== requestCompany) throw new QuoteError("creator_wrong_company");
}

export function coverageDocId(periodCode: string, uid: string): string {
  return `${periodCode}_${uid}`;
}

function coverageRef(db: Db, periodCode: string, uid: string) {
  return db.collection(COVERAGE).doc(coverageDocId(periodCode, uid));
}

function asDate(v: unknown): Date | null {
  if (v instanceof Date && !isNaN(v.getTime())) return v;
  if (v && typeof v === "object" && typeof (v as {toDate?: () => Date}).toDate === "function") {
    const d = (v as {toDate: () => Date}).toDate();
    return isNaN(d.getTime()) ? null : d;
  }
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }
  if (v && typeof v === "object" && typeof (v as {seconds?: number}).seconds === "number") {
    return new Date((v as {seconds: number}).seconds * 1000);
  }
  return null;
}

export function quotedAtOf(data: Data): Date | null {
  return asDate(data.quotedAt) || asDate(data.updatedAt) || asDate(data.createdAt) || asDate(data.createdAtServer);
}

function coverageBlocks(other: admin.firestore.DocumentSnapshot, now: Date): boolean {
  if (!other.exists) return false;
  const paymentStatus = str(other.get("paymentStatus"));
  // A paid request always blocks, even if staff later set status to
  // cancelled or rejected. Payment, not status, is the coverage source.
  if (paymentStatus === "paid") return true;
  const status = str(other.get("status"));
  if (status === "cancelled" || status === "rejected" || status === "expired") return false;
  if (paymentStatus === "expired" || paymentStatus === "failed" || paymentStatus === "waived" || paymentStatus === "not_required") {
    return false;
  }
  if (paymentStatus !== "pending") return false;
  const quoted = quotedAtOf((other.data() || {}) as Data);
  if (quoted && isRenewalCoverageExpired(quoted, now, str(other.get("periodCode")))) return false;
  return true;
}

export type TerminalReason = "staff_rejected" | "expired" | "cancelled";

function applyTerminalUpdate(
  tx: admin.firestore.Transaction,
  db: Db,
  requestId: string,
  data: Data,
  reason: TerminalReason,
): void {
  const paymentStatus = reason === "expired" ? "expired" : "failed";
  const update: admin.firestore.UpdateData<admin.firestore.DocumentData> = {
    paymentStatus,
    paymentError: reason,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (reason === "staff_rejected" && str(data.status) !== "rejected") update.status = "rejected";
  if (reason === "cancelled" && str(data.status) !== "cancelled") update.status = "cancelled";
  if (reason === "expired" && str(data.status) !== "expired") update.status = "expired";
  tx.update(db.collection(REQUESTS).doc(requestId), update);
}

async function readCoverageSnaps(
  tx: admin.firestore.Transaction,
  db: Db,
  periodCode: string,
  uids: string[],
): Promise<admin.firestore.DocumentSnapshot[]> {
  const snaps: admin.firestore.DocumentSnapshot[] = [];
  for (const uid of uids) {
    snaps.push(await tx.get(coverageRef(db, periodCode, uid)));
  }
  return snaps;
}

/**
 * Release a coverage claim only when this request still owns it. A late
 * finalize or failed Paymob callback must not overwrite a newer request's
 * claim. All snaps must have been read before any write in this transaction.
 */
function releaseCoverageIfOwned(
  tx: admin.firestore.Transaction,
  db: Db,
  requestId: string,
  periodCode: string,
  uids: string[],
  snaps: admin.firestore.DocumentSnapshot[],
): void {
  for (let i = 0; i < uids.length; i++) {
    const uid = uids[i];
    const cov = snaps[i];
    if (!cov || !cov.exists) continue;
    if (str(cov.get("requestId")) !== requestId) continue;
    tx.set(coverageRef(db, periodCode, uid), {
      requestId,
      uid,
      periodCode,
      status: "failed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

function canClaimCoverage(snap: admin.firestore.DocumentSnapshot | undefined, requestId: string): boolean {
  if (!snap || !snap.exists) return true;
  const owner = str(snap.get("requestId"));
  if (!owner || owner === requestId) return true;
  const status = str(snap.get("status"));
  return status === "failed";
}

/**
 * Mark a renewal terminal (rejected / cancelled / expired) and release its
 * coverage so the same uids can be renewed again. No-op for paid requests.
 */
export async function finalizeTerminalRenewal(db: Db, requestId: string, reason: TerminalReason): Promise<void> {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(db.collection(REQUESTS).doc(requestId));
    if (!snap.exists) return;
    const data = snap.data() as Data;
    if (str(data.requestType) !== REQUEST_TYPE_RENEWAL) return;
    if (str(data.paymentStatus) === "paid") return;
    const periodCode = str(data.periodCode);
    const uids = coveredUids(requestId, data);
    const covs = periodCode && uids.length ? await readCoverageSnaps(tx, db, periodCode, uids) : [];
    applyTerminalUpdate(tx, db, requestId, data, reason);
    if (periodCode && uids.length) releaseCoverageIfOwned(tx, db, requestId, periodCode, uids, covs);
  });
}

/**
 * Body of the `finalizeSubscriptionRenewalOnStatus` trigger. Exported so
 * tests can drive the same rejected→cancelled re-fire path without standing
 * up the functions emulator.
 */
export async function finalizeRenewalOnStatusChange(
  db: Db,
  requestId: string,
  before: Data,
  after: Data,
): Promise<void> {
  if (str(after.requestType || after.request_type) !== REQUEST_TYPE_RENEWAL) return;
  const status = str(after.status);
  if (status !== "rejected" && status !== "cancelled") return;
  const payment = str(after.paymentStatus);
  if (payment === "paid" || payment === "expired") return;
  if (payment === "failed" && str(after.paymentError) === (status === "rejected" ? "staff_rejected" : "cancelled")) {
    return;
  }
  const beforeStatus = str(before.status);
  if (beforeStatus === status && payment !== "pending") return;
  await finalizeTerminalRenewal(db, requestId, status === "rejected" ? "staff_rejected" : "cancelled");
}

/**
 * Scheduled / test hook: expire pending renewals whose quote is no longer
 * valid (end of the Cairo month it was quoted in, or the period end,
 * whichever comes first) and finish rejected/cancelled ones whose payment
 * is still pending.
 */
export async function expireAbandonedRenewals(db: Db, now: Date): Promise<{scanned: number, expired: number, finalized: number}> {
  const snap = await db.collection(REQUESTS)
    .where("requestType", "==", REQUEST_TYPE_RENEWAL)
    .where("paymentStatus", "==", "pending")
    .get();
  let expired = 0;
  let finalized = 0;
  for (const doc of snap.docs) {
    const data = doc.data() as Data;
    const payment = str(data.paymentStatus);
    const status = str(data.status);
    if (payment === "paid" || payment === "expired") continue;
    if (status === "rejected" && payment === "pending") {
      await finalizeTerminalRenewal(db, doc.id, "staff_rejected");
      finalized++;
      continue;
    }
    if (status === "cancelled" && payment === "pending") {
      await finalizeTerminalRenewal(db, doc.id, "cancelled");
      finalized++;
      continue;
    }
    if (payment !== "pending") continue;
    const quoted = quotedAtOf(data);
    if (quoted && isRenewalCoverageExpired(quoted, now, str(data.periodCode))) {
      await finalizeTerminalRenewal(db, doc.id, "expired");
      expired++;
    }
  }
  return {scanned: snap.size, expired, finalized};
}

/**
 * Transactional: a uid already on another pending or paid renewal for this
 * period cannot be quoted (or later charged) again. Cancelled, rejected,
 * failed, and expired requests do not block a retry. An abandoned pending
 * request past its coverage expiry is finalized in this transaction and
 * does not block. The same request may be re-quoted (refreshing expiry).
 */
async function assertNotAlreadyCovered(
  tx: admin.firestore.Transaction,
  db: Db,
  requestId: string,
  periodCode: string,
  uids: string[],
  now: Date,
): Promise<void> {
  const others = new Map<string, admin.firestore.DocumentSnapshot>();
  const coverageByUid = new Map<string, admin.firestore.DocumentSnapshot>();
  for (const uid of uids) {
    const cov = await tx.get(coverageRef(db, periodCode, uid));
    coverageByUid.set(uid, cov);
    if (!cov.exists) continue;
    const otherId = str(cov.get("requestId"));
    if (!otherId || otherId === requestId) continue;
    if (!others.has(otherId)) {
      others.set(otherId, await tx.get(db.collection(REQUESTS).doc(otherId)));
    }
  }
  for (const [otherId, other] of others) {
    if (!other.exists) continue;
    const data = (other.data() || {}) as Data;
    const status = str(data.status);
    const payment = str(data.paymentStatus);
    const otherUids = coveredUids(otherId, data).filter((u) => uids.includes(u));
    const release = () => {
      if (!periodCode || !otherUids.length) return;
      const owned: string[] = [];
      const snaps: admin.firestore.DocumentSnapshot[] = [];
      for (const uid of otherUids) {
        const snap = coverageByUid.get(uid);
        if (!snap) continue;
        owned.push(uid);
        snaps.push(snap);
      }
      releaseCoverageIfOwned(tx, db, otherId, periodCode, owned, snaps);
    };
    if (status === "rejected" && payment === "pending") {
      applyTerminalUpdate(tx, db, otherId, data, "staff_rejected");
      release();
      continue;
    }
    if (status === "cancelled" && payment === "pending") {
      applyTerminalUpdate(tx, db, otherId, data, "cancelled");
      release();
      continue;
    }
    const quoted = quotedAtOf(data);
    if (payment === "pending" && quoted && isRenewalCoverageExpired(quoted, now, str(data.periodCode))) {
      applyTerminalUpdate(tx, db, otherId, data, "expired");
      release();
      continue;
    }
    if (coverageBlocks(other, now)) throw new QuoteError("already_covered");
  }
}

function claimCoverage(
  tx: admin.firestore.Transaction,
  db: Db,
  requestId: string,
  periodCode: string,
  uids: string[],
  status: "pending" | "paid" | "failed",
): void {
  for (const uid of uids) {
    tx.set(coverageRef(db, periodCode, uid), {
      requestId,
      uid,
      periodCode,
      status,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

/**
 * When the calendar month changes inside the same period, the prorated
 * fee changes (500 × remainingMonths / 6). Write the fresh quote onto the
 * pending request so checkout charges the new amount, not a stale one.
 */
async function persistRecomputedQuote(
  tx: admin.firestore.Transaction,
  db: Db,
  requestId: string,
  data: Data,
  quote: Quote,
  at: Date,
): Promise<void> {
  const storedCents = toCents(Number(data.amountDue ?? data.fee ?? 0));
  const storedMonths = Number(data.remainingMonths ?? 0);
  const quotedAt = Timestamp.fromDate(at);
  if (storedCents === quote.amountCents && storedMonths === quote.remainingMonths) {
    tx.update(db.collection(REQUESTS).doc(requestId), {quotedAt, updatedAt: FieldValue.serverTimestamp()});
    return;
  }
  const existingItems = Array.isArray(data.items) ? data.items as Data[] : [];
  const nameByUid = new Map(existingItems.map((i) => [str(i.uid), str(i.fullName)]));
  const items = quote.items.map((i) => ({
    uid: i.uid,
    fullName: nameByUid.get(i.uid) || "",
    fee: i.fee,
  }));
  tx.update(db.collection(REQUESTS).doc(requestId), {
    amountDue: quote.amount,
    fee: quote.amount,
    remainingMonths: quote.remainingMonths,
    items,
    quotedAt,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Every renewed uid must be an app-added delegate of the requesting company. */
async function assertRenewable(db: Db, request: Data, uids: string[]): Promise<void> {
  const company = str(request.companyUID);
  const regs = await db.getAll(...uids.map((uid) => db.collection(REQUESTS).doc(uid)));
  for (const reg of regs) {
    if (!reg.exists || !isAppAddedRegistration(reg.id, reg.data() as Data)) {
      throw new QuoteError("not_app_added");
    }
    if (company === "" || str(reg.get("companyUID")) !== company) throw new QuoteError("wrong_company");
  }
}

export interface VerifiedPayment {
  /** delegate_requests doc id that Engineering put in the Paymob order (merchant_order_id / extras). */
  requestId: string;
  paymobTransactionId: string;
  paymobOrderId?: string;
  success: boolean;
  amountCents: number;
  currency: string;
  /** Paymob transaction time. */
  paidAt: Date;
}

export type ApplyOutcome =
  | "duplicate" | "not_found" | "already_paid" | "failed" | "rejected" | "paid";

/**
 * Hook for Engineering's Paymob webhook. Call ONLY after the Paymob HMAC has
 * been verified server-side. Idempotent per Paymob transaction id.
 * - success=false: request -> failed, nobody is (re)activated.
 * - amount/period/delegate mismatch: request -> failed + needsReview, nobody is activated.
 * - success: request -> paid; renewal delegates are reactivated for the period;
 *   a new_delegate stays pending until staff approve the documents.
 */
export async function applyVerifiedSubscriptionPayment(db: Db, p: VerifiedPayment): Promise<ApplyOutcome> {
  const txId = str(p.paymobTransactionId);
  if (txId === "" || str(p.requestId) === "") throw new Error("requestId and paymobTransactionId are required");
  const eventRef = db.collection(EVENTS).doc(txId);
  const reqRef = db.collection(REQUESTS).doc(p.requestId);
  const ts = FieldValue.serverTimestamp();
  const paymob = {
    transactionId: txId,
    orderId: str(p.paymobOrderId),
    amountCents: p.amountCents,
    currency: p.currency,
    success: p.success,
    paidAt: Timestamp.fromDate(p.paidAt),
  };

  let rejectReason = "";
  if (p.success) {
    try {
      const quote = await quoteSubscriptionRequest(db, p.requestId, p.paidAt);
      if (str(p.currency).toUpperCase() !== "EGP") rejectReason = "currency_mismatch";
      else if (quote.amountCents !== p.amountCents) rejectReason = "amount_mismatch";
    } catch (e) {
      rejectReason = e instanceof QuoteError ? e.reason : "quote_failed";
    }
  }

  const outcome = await db.runTransaction(async (tx): Promise<ApplyOutcome> => {
    const [event, req] = await Promise.all([tx.get(eventRef), tx.get(reqRef)]);
    const data = (req.exists ? (req.data() || {}) : {}) as Data;
    const periodCode = str(data.periodCode);
    const uids = req.exists ? coveredUids(p.requestId, data) : [];
    const covs = periodCode && uids.length ? await readCoverageSnaps(tx, db, periodCode, uids) : [];
    if (event.exists) return "duplicate";
    tx.set(eventRef, {requestId: p.requestId, ...paymob, receivedAt: ts});
    if (!req.exists) return "not_found";
    if (str(req.get("paymentStatus")) === "paid") return "already_paid";
    if (!p.success) {
      tx.update(reqRef, {paymentStatus: "failed", paymob, paymentError: "payment_failed", updatedAt: ts});
      if (periodCode && uids.length) releaseCoverageIfOwned(tx, db, p.requestId, periodCode, uids, covs);
      return "failed";
    }
    if (rejectReason !== "" && rejectReason !== "already_paid") {
      tx.update(reqRef, {
        paymentStatus: "failed", paymob, paymentError: rejectReason, needsReview: true, updatedAt: ts,
      });
      if (periodCode && uids.length) releaseCoverageIfOwned(tx, db, p.requestId, periodCode, uids, covs);
      return "rejected";
    }
    const isRenewal = str(req.get("requestType")) === REQUEST_TYPE_RENEWAL;
    const stealsCoverage = periodCode && uids.length && covs.some((s) => !canClaimCoverage(s, p.requestId));
    tx.update(reqRef, {
      paymentStatus: "paid",
      paymob,
      amountPaid: p.amountCents / 100,
      paidAt: paymob.paidAt,
      paymentError: FieldValue.delete(),
      applyState: "pending",
      ...(isRenewal ? {status: "approved", reviewedBy: "Paymob", reviewedAt: new Date().toISOString()} : {}),
      ...(stealsCoverage ? {needsReview: true, paymentError: "coverage_held_elsewhere"} : {}),
      updatedAt: ts,
    });
    if (periodCode && uids.length && !stealsCoverage) {
      claimCoverage(tx, db, p.requestId, periodCode, uids, "paid");
    }
    return "paid";
  });

  if (outcome === "paid") await applyPaidRequest(db, p.requestId, p.paidAt);
  console.log(JSON.stringify({event: "subscription_payment", requestId: p.requestId, txId, outcome, rejectReason}));
  return outcome;
}

/**
 * Writes the paid subscription onto the delegate docs. A paid renewal
 * removes the subscription_expired hold through holds.ts (renewal only;
 * other holds stay). Shadow mode does not write users/{uid}; it still reactivates when only an expiry hold (or legacy expiry reason) remains.
 * Re-runnable: call it again for a request whose applyState is not "applied".
 */
function resolveApplyAsOf(asOf: Date | undefined, data: Data): Date {
  if (asOf instanceof Date && !Number.isNaN(asOf.getTime())) return asOf;
  const raw = data.paidAt;
  if (raw instanceof Timestamp) return raw.toDate();
  if (raw instanceof Date && !Number.isNaN(raw.getTime())) return raw;
  if (typeof raw === "string") {
    const d = new Date(raw);
    if (!Number.isNaN(d.getTime())) return d;
  }
  if (raw && typeof raw === "object" && typeof (raw as {toDate?: unknown}).toDate === "function") {
    const d = (raw as {toDate: () => Date}).toDate();
    if (d instanceof Date && !Number.isNaN(d.getTime())) return d;
  }
  return new Date();
}

export async function applyPaidRequest(db: Db, requestId: string, asOf?: Date): Promise<number> {
  const reqRef = db.collection(REQUESTS).doc(requestId);
  const req = await reqRef.get();
  if (!req.exists || str(req.get("paymentStatus")) !== "paid") return 0;
  const data = req.data() as Data;
  const period = parsePeriodCode(data.periodCode);
  if (!period) return 0;
  const now = resolveApplyAsOf(asOf, data);
  const isRenewal = str(data.requestType) === REQUEST_TYPE_RENEWAL;
  // Only drop the expiry hold when the payment is for the current period.
  // An advance payment for the next period must not reactivate early.
  const clearsExpiryHold = isRenewal && period.code === periodOf(now).code;
  const uids = coveredUids(requestId, data);
  const fees = new Map<string, number>();
  if (Array.isArray(data.items)) {
    for (const item of data.items as Data[]) fees.set(str(item.uid), Number(item.fee) || 0);
  }
  const ts = FieldValue.serverTimestamp();
  const writer = new Batcher(db);
  let reactivated = 0;
  const subscriptionFor = (uid: string) => ({
    periodCode: period.code,
    periodStart: period.startDay,
    periodEnd: period.endDay,
    amountDue: fees.get(uid) ?? (Number(data.amountDue) || 0),
    paymentStatus: "paid",
    renewalRequestId: isRenewal ? requestId : null,
    registrationRequestId: isRenewal ? null : requestId,
    paidAt: data.paidAt ?? null,
  });
  const at = now.toISOString();
  const mode = process.env.HOLDS_AUTHORITY_MODE;
  for (const doc of await delegateDocsFor(db, uids)) {
    const uid = str(doc.get("uid")) || doc.ref.id;
    const update: Data = {};
    const sub = subscriptionFor(uid);
    // An advance payment for a future period must not overwrite the
    // current subscription map. It is stored separately as nextSubscription.
    if (isRenewal && !clearsExpiryHold) {
      update.nextSubscription = sub;
    } else {
      update.subscription = sub;
      const existingNext = doc.get("nextSubscription") as Data | undefined;
      if (existingNext && str(existingNext.periodCode) === period.code) {
        update.nextSubscription = FieldValue.delete();
      }
    }
    // Renewal payment only: remove the expiry hold. Other holds stay.
    // new_delegate payments never reactivate (V1). Future-period
    // (advance) payments write coverage now and leave the hold until
    // that period starts (M1 then clears it for covered uids).
    if (clearsExpiryHold) {
      const planned = planExpiryHoldWrite({
        data: (doc.data() || {}) as Data,
        op: "remove",
        at,
        actor: "paymob",
        source: M2_SOURCE,
        requestId: requestId,
        periodCode: period.code,
        mode,
        inferLegacyExpiry: true,
      });
      if (planned.ok && !planned.unchanged) {
        Object.assign(update, planned.update);
        if (planned.plan.history && Object.keys(planned.plan.history).length) {
          await writer.set(doc.ref.collection("statusHistory").doc(), {
            ...planned.plan.history,
            writtenAt: ts,
          });
        }
      }
      // Even in shadow mode: if no holds remain, reactivate like the
      // legacy path so a paid delegate is not left suspended. Do not
      // clear a legacy admin / device-unbind / manual suspension that
      // has no holds map.
      if (planned.ok && shouldShadowReactivateAfterExpiryClear(
        (doc.data() || {}) as Data,
        planned.plan.derivedStatus,
      )) {
        update.status = "active";
        update.statusReason = FieldValue.delete();
        reactivated++;
      } else if (planned.ok && !planned.unchanged) {
        reactivated++;
      }
    }
    await writer.update(doc.ref, withWriteMeta(update, ts));
  }
  // users/{uid} is mirrored by the holds trigger once it is authoritative.
  await writer.flush();
  await reqRef.update({applyState: "applied", reactivatedDocs: reactivated, appliedAt: ts});
  return reactivated;
}
