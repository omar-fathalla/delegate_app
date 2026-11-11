import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  PaymentStatus,
  Period,
  Quote,
  QuoteOptions,
  REQUEST_TYPE_NEW,
  REQUEST_TYPE_RENEWAL,
  SUSPEND_REASON,
  coveredUids,
  isAppAddedRegistration,
  isFreePromotion,
  isRenewalCoverageExpired,
  parsePeriodCode,
  periodOf,
  quoteFor,
  toCents,
  requestCoversPeriod,
  shouldSuspendStatus,
  MAX_DELEGATES_PER_RENEWAL,
} from "./subscription_logic";

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
}

/**
 * Suspends every app-added delegate that has no paid subscription for the
 * current period. Idempotent: already-suspended docs are left as they are
 * (so manual suspensions are never overwritten), and web delegates are
 * never selected. Runs daily so a missed run or a client-side reactivation
 * is corrected on the next run.
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

  for (const doc of await delegateDocsFor(db, candidates)) {
    const status = doc.get("status");
    if (str(status).toLowerCase() === "suspended") {
      res.alreadySuspended++;
      continue;
    }
    if (!shouldSuspendStatus(status)) continue;
    await writer.update(doc.ref, {
      "status": "suspended",
      "statusReason": SUSPEND_REASON,
      "subscription.suspendedForPeriod": period.code,
      "subscription.suspendedAt": ts,
      "updatedAt": ts,
    });
    res.suspendedDocs++;
  }
  for (const part of chunks(candidates, 100)) {
    const snaps = await db.getAll(...part.map((uid) => db.collection("users").doc(uid)));
    for (const snap of snaps) {
      if (!snap.exists || !shouldSuspendStatus(snap.get("status"))) continue;
      await writer.update(snap.ref, {status: "suspended", statusReason: SUSPEND_REASON, updatedAt: ts});
      res.suspendedUsers++;
    }
  }
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
  if (str(data.periodCode) !== periodOf(at).code) throw new QuoteError("period_mismatch");
  const uids = coveredUids(requestId, data);
  if (uids.length === 0) throw new QuoteError("no_delegates");
  if (uids.length > MAX_DELEGATES_PER_RENEWAL) throw new QuoteError("too_many_delegates");
  await assertCreatorScope(db, data);
  if (type === REQUEST_TYPE_RENEWAL) await assertRenewable(db, data, uids);
  const quoteOpts = await loadDevQuoteOptions(db, data);
  const quote = quoteFor(uids, at, quoteOpts);
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
  const status = str(other.get("status"));
  const paymentStatus = str(other.get("paymentStatus"));
  if (status === "cancelled" || status === "rejected") return false;
  if (paymentStatus === "expired" || paymentStatus === "failed" || paymentStatus === "waived" || paymentStatus === "not_required") {
    return false;
  }
  if (paymentStatus === "paid") return true;
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
  const update: Data = {
    paymentStatus,
    paymentError: reason,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (reason === "staff_rejected" && str(data.status) !== "rejected") update.status = "rejected";
  if (reason === "cancelled" && str(data.status) !== "cancelled") update.status = "cancelled";
  tx.update(db.collection(REQUESTS).doc(requestId), update);
  const periodCode = str(data.periodCode);
  const uids = coveredUids(requestId, data);
  if (periodCode && uids.length) claimCoverage(tx, db, requestId, periodCode, uids, "failed");
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
    applyTerminalUpdate(tx, db, requestId, data, reason);
  });
}

/**
 * Scheduled / test hook: expire pending renewals whose quote is no longer
 * valid (end of the Cairo month it was quoted in, or the period end,
 * whichever comes first) and finish rejected/cancelled ones whose payment
 * is still pending.
 */
export async function expireAbandonedRenewals(db: Db, now: Date): Promise<{scanned: number, expired: number, finalized: number}> {
  const snap = await db.collection(REQUESTS).where("requestType", "==", REQUEST_TYPE_RENEWAL).get();
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
  for (const uid of uids) {
    const cov = await tx.get(coverageRef(db, periodCode, uid));
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
    if (status === "rejected" && payment === "pending") {
      applyTerminalUpdate(tx, db, otherId, data, "staff_rejected");
      continue;
    }
    if (status === "cancelled" && payment === "pending") {
      applyTerminalUpdate(tx, db, otherId, data, "cancelled");
      continue;
    }
    const quoted = quotedAtOf(data);
    if (payment === "pending" && quoted && isRenewalCoverageExpired(quoted, now, str(data.periodCode))) {
      applyTerminalUpdate(tx, db, otherId, data, "expired");
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
    if (event.exists) return "duplicate";
    tx.set(eventRef, {requestId: p.requestId, ...paymob, receivedAt: ts});
    if (!req.exists) return "not_found";
    if (str(req.get("paymentStatus")) === "paid") return "already_paid";
    const data = (req.data() || {}) as Data;
    const periodCode = str(data.periodCode);
    const uids = coveredUids(p.requestId, data);
    if (!p.success) {
      tx.update(reqRef, {paymentStatus: "failed", paymob, paymentError: "payment_failed", updatedAt: ts});
      if (periodCode && uids.length) claimCoverage(tx, db, p.requestId, periodCode, uids, "failed");
      return "failed";
    }
    if (rejectReason !== "" && rejectReason !== "already_paid") {
      tx.update(reqRef, {
        paymentStatus: "failed", paymob, paymentError: rejectReason, needsReview: true, updatedAt: ts,
      });
      if (periodCode && uids.length) claimCoverage(tx, db, p.requestId, periodCode, uids, "failed");
      return "rejected";
    }
    const isRenewal = str(req.get("requestType")) === REQUEST_TYPE_RENEWAL;
    tx.update(reqRef, {
      paymentStatus: "paid",
      paymob,
      amountPaid: p.amountCents / 100,
      paidAt: paymob.paidAt,
      paymentError: FieldValue.delete(),
      applyState: "pending",
      ...(isRenewal ? {status: "approved", reviewedBy: "Paymob", reviewedAt: new Date().toISOString()} : {}),
      updatedAt: ts,
    });
    if (periodCode && uids.length) claimCoverage(tx, db, p.requestId, periodCode, uids, "paid");
    return "paid";
  });

  if (outcome === "paid") await applyPaidRequest(db, p.requestId);
  console.log(JSON.stringify({event: "subscription_payment", requestId: p.requestId, txId, outcome, rejectReason}));
  return outcome;
}

/**
 * Writes the paid subscription onto the delegate docs. Re-runnable: call it
 * again for a request whose applyState is not "applied".
 */
export async function applyPaidRequest(db: Db, requestId: string): Promise<number> {
  const reqRef = db.collection(REQUESTS).doc(requestId);
  const req = await reqRef.get();
  if (!req.exists || str(req.get("paymentStatus")) !== "paid") return 0;
  const data = req.data() as Data;
  const period = parsePeriodCode(data.periodCode);
  if (!period) return 0;
  const isRenewal = str(data.requestType) === REQUEST_TYPE_RENEWAL;
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
  for (const doc of await delegateDocsFor(db, uids)) {
    const uid = str(doc.get("uid"));
    const update: Data = {subscription: subscriptionFor(uid), updatedAt: ts};
    if (isRenewal && str(doc.get("status")) === "suspended" && str(doc.get("statusReason")) === SUSPEND_REASON) {
      update.status = "active";
      update.statusReason = FieldValue.delete();
      reactivated++;
    }
    await writer.update(doc.ref, update);
  }
  if (isRenewal) {
    const users = await db.getAll(...uids.map((uid) => db.collection("users").doc(uid)));
    for (const u of users) {
      if (u.exists && str(u.get("status")) === "suspended" && str(u.get("statusReason")) === SUSPEND_REASON) {
        await writer.update(u.ref, {
          status: "active", statusReason: FieldValue.delete(), updatedAt: ts,
        });
      }
    }
  }
  await writer.flush();
  await reqRef.update({applyState: "applied", reactivatedDocs: reactivated, appliedAt: ts});
  return reactivated;
}
