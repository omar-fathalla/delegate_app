/**
 * Paymob test-mode checkout and webhook for one subscription renewal
 * (or registration) payment. The amount comes from quoteSubscriptionRequest;
 * the client never sends an amount or holds Paymob keys.
 *
 * Deploy (tashil-dev only, named):
 *   functions:tashil-mobile-notifications:createSubscriptionCheckout
 *   functions:tashil-mobile-notifications:paymobSubscriptionWebhook
 * Never deploy suspendExpiredSubscriptions with these. Test-mode keys only:
 * classic sk_test_ / pk_test_, or the same prefix after a 2-5 letter region
 * (egy_sk_test_ / egy_pk_test_). Live keys are refused, including regional
 * ones (sk_live_, pk_live_, egy_sk_live_, egy_pk_live_).
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  QuoteError,
  applyVerifiedSubscriptionPayment,
  expireAbandonedRenewals,
  previewRenewalQuote,
  quoteSubscriptionRequest,
} from "./subscription_jobs";
import {CHECKOUT_IN_PROGRESS_SECONDS, isAwaitingPaymentExpired} from "./subscription_logic";
import {verifyTransactionPostHmac} from "./paymob_hmac";
import {notifyPaymobSupersededPaymentRefund, PaymobMessaging} from "./paymob_superseded_alert";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 60, memory: "256MB" as const};
const EGYPT_BASE = "https://accept.paymob.com";
const WEBHOOK_NAME = "paymobSubscriptionWebhook";
/** Suffix delimiter: `{requestId}__{attemptId}` — legacy checkouts used bare `requestId`. */
export const PAYMOB_SPECIAL_REF_DELIMITER = "__";
const CHECKOUT_ATTEMPTS = "paymob_checkout_attempts";
const SUPERSEDED_PAYMENTS = "paymob_superseded_payments";
/** Matches `newCheckoutAttemptId()` (`{epochMs}_{base36}`). */
export const CHECKOUT_ATTEMPT_ID_PATTERN = /^\d+_[a-z0-9]+$/;

export class PaymobIntentionError extends Error {
  readonly reason: string;
  readonly httpStatus?: number;
  constructor(reason: string, httpStatus?: number) {
    super(reason);
    this.name = "PaymobIntentionError";
    this.reason = reason;
    this.httpStatus = httpStatus;
  }
}

export function newCheckoutAttemptId(at: Date = new Date()): string {
  return `${at.getTime()}_${Math.random().toString(36).slice(2, 10)}`;
}

export function buildPaymobSpecialReference(requestId: string, attemptId: string): string {
  return `${requestId}${PAYMOB_SPECIAL_REF_DELIMITER}${attemptId}`;
}

export function isValidCheckoutAttemptId(attemptId: string): boolean {
  return CHECKOUT_ATTEMPT_ID_PATTERN.test(str(attemptId));
}

export function splitPaymobReference(ref: string): {requestId: string; attemptId: string} {
  const trimmed = str(ref);
  if (trimmed === "") return {requestId: "", attemptId: ""};
  const idx = trimmed.lastIndexOf(PAYMOB_SPECIAL_REF_DELIMITER);
  if (idx < 0) return {requestId: trimmed, attemptId: ""};
  const attemptId = trimmed.slice(idx + PAYMOB_SPECIAL_REF_DELIMITER.length);
  const requestId = trimmed.slice(0, idx);
  if (attemptId && !isValidCheckoutAttemptId(attemptId)) {
    return {requestId: trimmed, attemptId: ""};
  }
  return {requestId, attemptId};
}

/** Maps Paymob `special_reference` / merchant order id back to `delegate_requests` doc id. */
export function resolveRequestIdFromPaymobReference(ref: string): string {
  return splitPaymobReference(ref).requestId;
}

export function attemptIdFromPaymobReference(ref: string): string {
  return splitPaymobReference(ref).attemptId;
}

export function paymobReferenceFromObj(obj: Record<string, unknown>): string {
  const order = (obj.order && typeof obj.order === "object")
    ? obj.order as Record<string, unknown>
    : {};
  return str(order.merchant_order_id) || str(obj.merchant_order_id) ||
    str(obj.special_reference) || str(order.special_reference);
}

/**
 * Paymob Accept **test** integration for tashil-dev User Test (Task H / Phase 3).
 * Set `PAYMOB_INTEGRATION_IDS=5882985` on deployed functions (never commit keys).
 * Do not use live integration IDs (`6033728` / `6033727`).
 */
export const TASHIL_DEV_PAYMOB_INTEGRATION_ID = 5882985;

/** Live Accept integration IDs — must never be used on Cloud Functions (test keys only). */
export const PAYMOB_FORBIDDEN_LIVE_INTEGRATION_IDS = new Set([
  6033727,
  6033728,
]);

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Paymob sends transaction and order ids as numbers in the JSON body. */
function idStr(v: unknown): string {
  if (typeof v === "string") return v.trim();
  if (typeof v === "number" && Number.isFinite(v)) return String(Math.trunc(v));
  return "";
}

function fail(code: functions.https.FunctionsErrorCode, reason: string, message?: string): never {
  throw new functions.https.HttpsError(code, message || reason, {reason});
}

export interface PaymobEnv {
  baseUrl: string;
  secretKey: string;
  publicKey: string;
  hmacSecret: string;
  integrationIds: number[];
}

/** Classic test keys, or the same kind after a 2-5 letter region (egy_sk_test_...). */
const PAYMOB_TEST_SECRET_KEY = /^(?:[a-z]{2,5}_)?sk_test_/;
const PAYMOB_TEST_PUBLIC_KEY = /^(?:[a-z]{2,5}_)?pk_test_/;
/** Live keys at the start or after any prefix (sk_live_..., egy_sk_live_...). */
const PAYMOB_LIVE_SECRET_KEY = /(?:^|_)sk_live_/;
const PAYMOB_LIVE_PUBLIC_KEY = /(?:^|_)pk_live_/;

export function readPaymobEnv(env: NodeJS.ProcessEnv = process.env): PaymobEnv | {error: string} {
  const secretKey = str(env.PAYMOB_SECRET_KEY);
  const publicKey = str(env.PAYMOB_PUBLIC_KEY);
  const hmacSecret = str(env.PAYMOB_HMAC_SECRET);
  const baseUrl = str(env.PAYMOB_BASE_URL) || EGYPT_BASE;
  const rawIds = str(env.PAYMOB_INTEGRATION_IDS) || str(env.PAYMOB_INTEGRATION_ID_CARD);
  const integrationIds = rawIds
    .split(",")
    .map((s) => Number(s.trim()))
    .filter((n) => Number.isInteger(n) && n > 0);
  if (!secretKey || !publicKey || !hmacSecret || integrationIds.length === 0) {
    return {error: "paymob_not_configured"};
  }
  if (str(env.PAYMOB_LIVE).toLowerCase() === "true" || str(env.PAYMOB_MODE).toLowerCase() === "live") {
    return {error: "paymob_live_forbidden"};
  }
  if (PAYMOB_LIVE_SECRET_KEY.test(secretKey) || PAYMOB_LIVE_PUBLIC_KEY.test(publicKey)) {
    return {error: "paymob_live_forbidden"};
  }
  if (integrationIds.some((id) => PAYMOB_FORBIDDEN_LIVE_INTEGRATION_IDS.has(id))) {
    return {error: "paymob_live_forbidden"};
  }
  if (!PAYMOB_TEST_SECRET_KEY.test(secretKey) || !PAYMOB_TEST_PUBLIC_KEY.test(publicKey)) {
    return {error: "paymob_test_keys_required"};
  }
  if (!baseUrl.startsWith("https://accept.paymob.com") &&
      !baseUrl.startsWith("https://uae.paymob.com") &&
      !baseUrl.startsWith("https://ksa.paymob.com") &&
      !baseUrl.startsWith("https://oman.paymob.com")) {
    return {error: "paymob_bad_base_url"};
  }
  return {baseUrl: baseUrl.replace(/\/$/, ""), secretKey, publicKey, hmacSecret, integrationIds};
}

export function checkoutUrl(baseUrl: string, publicKey: string, clientSecret: string): string {
  const u = new URL("/unifiedcheckout/", baseUrl);
  u.searchParams.set("publicKey", publicKey);
  u.searchParams.set("clientSecret", clientSecret);
  return u.toString();
}

export function webhookUrl(projectId: string, region = "us-central1"): string {
  return `https://${region}-${projectId}.cloudfunctions.net/${WEBHOOK_NAME}`;
}

function boolFlag(v: unknown): boolean {
  return v === true || String(v) === "true";
}

function asTime(v: unknown): Date | null {
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v;
  if (v && typeof v === "object" && typeof (v as {toDate?: () => Date}).toDate === "function") {
    const d = (v as {toDate: () => Date}).toDate();
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (v && typeof v === "object" && typeof (v as {seconds?: number}).seconds === "number") {
    return new Date((v as {seconds: number}).seconds * 1000);
  }
  return null;
}

/** True when a second checkout would collide with an intention just created. */
export function isCheckoutInProgress(req: Record<string, unknown>, now: Date): boolean {
  const checkout = (req.paymobCheckout && typeof req.paymobCheckout === "object")
    ? req.paymobCheckout as Record<string, unknown>
    : {};
  const at = asTime(checkout.createdAt);
  if (!at) return false;
  return now.getTime() - at.getTime() < CHECKOUT_IN_PROGRESS_SECONDS * 1000;
}

const RENEWAL_ROLES = new Set([
  "admin", "company-admin", "company_admin", "companyadmin",
  "supervisor", "company_supervisor",
  "hr", "company-hr", "company_hr", "human_resources",
  "organization-admin", "organization_admin", "organizationadmin", "organizationAdmin",
  "super-admin", "super_admin", "superadmin", "superAdmin",
]);

async function assertCallerMayPay(
  db: admin.firestore.Firestore,
  uid: string,
  request: Record<string, unknown>,
): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists) fail("permission-denied", "caller_not_staff");
  const role = str(snap.get("role"));
  if (!RENEWAL_ROLES.has(role)) fail("permission-denied", "caller_not_allowed");
  if (role === "super-admin" || role === "super_admin" || role === "superadmin" || role === "superAdmin") {
    return;
  }
  const callerOrg = str(snap.get("organizationUID") || snap.get("organizationId"));
  const callerCompany = str(snap.get("companyUID") || snap.get("companyId"));
  const requestOrg = str(request.organizationUID || request.organizationId);
  const requestCompany = str(request.companyUID || request.companyId);
  if (!callerCompany || callerCompany !== requestCompany) {
    fail("permission-denied", "out_of_scope");
  }
  if (role.startsWith("organization") || role.includes("organization")) {
    if (!callerOrg || callerOrg !== requestOrg) fail("permission-denied", "out_of_scope");
  }
}

function billingFromRequest(data: Record<string, unknown>, uid: string): {
  first_name: string; last_name: string; email: string; phone_number: string;
} {
  const name = str(data.supervisorName) || str(data.fullName) || "Tashil";
  const parts = name.split(/\s+/).filter(Boolean);
  const first = parts[0] || "Tashil";
  const last = parts.slice(1).join(" ") || "Staff";
  const phone = str(data.supervisorPhone) || str(data.phoneNumber) || "01000000000";
  const email = `${uid.replace(/[^a-zA-Z0-9]/g, "_")}@tashil-dev.test`;
  return {first_name: first, last_name: last, email, phone_number: phone};
}

export interface IntentionResult {
  id: string;
  clientSecret: string;
  checkoutUrl: string;
  publicKey: string;
  amountCents: number;
}

export async function createPaymobIntention(opts: {
  env: PaymobEnv;
  amountCents: number;
  specialReference: string;
  notificationUrl: string;
  redirectionUrl?: string;
  billing: ReturnType<typeof billingFromRequest>;
  itemName: string;
  itemCount: number;
  fetchImpl?: typeof fetch;
}): Promise<IntentionResult> {
  const body = {
    amount: opts.amountCents,
    currency: "EGP",
    payment_methods: opts.env.integrationIds,
    special_reference: opts.specialReference,
    notification_url: opts.notificationUrl,
    redirection_url: opts.redirectionUrl || opts.notificationUrl,
    items: [{
      name: opts.itemName,
      amount: opts.amountCents,
      quantity: 1,
      description: `${opts.itemCount} delegates`,
    }],
    billing_data: {
      ...opts.billing,
      apartment: "NA",
      floor: "NA",
      street: "NA",
      building: "NA",
      shipping_method: "NA",
      postal_code: "NA",
      city: "NA",
      state: "NA",
      country: "EGY",
    },
    customer: {
      first_name: opts.billing.first_name,
      last_name: opts.billing.last_name,
      email: opts.billing.email,
    },
  };
  const res = await (opts.fetchImpl || fetch)(`${opts.env.baseUrl}/v1/intention/`, {
    method: "POST",
    headers: {
      Authorization: `Token ${opts.env.secretKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    const lower = text.toLowerCase();
    const duplicateRef = res.status === 400 &&
      (lower.includes("ref already exists") || lower.includes("already exists"));
    const reason = duplicateRef ? "paymob_duplicate_reference" : "paymob_intention_failed";
    console.error(JSON.stringify({event: "paymob_intention_failed", status: res.status, reason}));
    throw new PaymobIntentionError(reason, res.status);
  }
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new PaymobIntentionError("paymob_intention_failed");
  }
  const clientSecret = str(data.client_secret);
  const id = str(data.id);
  if (!clientSecret || !id) throw new PaymobIntentionError("paymob_intention_failed");
  return {
    id,
    clientSecret,
    checkoutUrl: checkoutUrl(opts.env.baseUrl, opts.env.publicKey, clientSecret),
    publicKey: opts.env.publicKey,
    amountCents: opts.amountCents,
  };
}

export const createSubscriptionCheckout = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth || context.auth.token.firebase?.sign_in_provider === "anonymous") {
      fail("unauthenticated", "sign_in_required");
    }
    const requestId = str((data as {requestId?: unknown} | null)?.requestId);
    if (!requestId) fail("invalid-argument", "request_id_required", "معرّف طلب التجديد مطلوب.");
    // Authz first: a signed-in user who cannot pay this request must not
    // learn whether Paymob is configured.
    const db = admin.firestore();
    const snap = await db.collection("delegate_requests").doc(requestId).get();
    if (!snap.exists) fail("not-found", "not_found", "طلب التجديد غير موجود.");
    const req = (snap.data() || {}) as Record<string, unknown>;
    await assertCallerMayPay(db, context.auth!.uid, req);
    const now = new Date();
    if (isCheckoutInProgress(req, now) && str(req.paymentStatus) === "pending") {
      fail("failed-precondition", "checkout_in_progress", quoteErrorMessage("checkout_in_progress"));
    }
    if (str(req.paymentStatus) === "pending" && isAwaitingPaymentExpired(req, now)) {
      await expireAbandonedRenewals(db, now);
    }
    const env = readPaymobEnv();
    if ("error" in env) {
      const msg = env.error === "paymob_live_forbidden" || env.error === "paymob_test_keys_required"
        ? "دفع Paymob على بيئة الاختبار فقط. مفاتيح الإنتاج مرفوضة."
        : "تم حفظ الطلب بانتظار الدفع، لكن دفع Paymob غير مضبوط على الخادم بعد.";
      fail("failed-precondition", env.error, msg);
    }
    let quote;
    try {
      quote = await quoteSubscriptionRequest(db, requestId, new Date());
    } catch (e) {
      const reason = e instanceof QuoteError ? e.reason : "quote_failed";
      fail("failed-precondition", reason, quoteErrorMessage(reason));
    }
    const projectId = str(admin.app().options.projectId) ||
      str(process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT) || "tashil-dev";
    const uids = Array.isArray(req.coveredDelegateUids) ? req.coveredDelegateUids.length : 1;
    const attemptId = newCheckoutAttemptId(now);
    const specialReference = buildPaymobSpecialReference(requestId, attemptId);
    let intention: IntentionResult;
    try {
      intention = await createPaymobIntention({
        env,
        amountCents: quote.amountCents,
        specialReference,
        notificationUrl: webhookUrl(projectId),
        billing: billingFromRequest(req, context.auth.uid),
        itemName: `تجديد ${quote.periodCode}`,
        itemCount: uids || 1,
      });
    } catch (e) {
      if (e instanceof PaymobIntentionError) {
        if (e.reason === "paymob_duplicate_reference") {
          fail(
            "failed-precondition",
            e.reason,
            "توجد محاولة دفع قيد المعالجة لدى Paymob. انتظر قليلاً ثم أعد فتح الدفع.",
          );
        }
        fail("internal", e.reason, "تعذر تجهيز صفحة الدفع. أعد المحاولة بعد قليل.");
      }
      fail("internal", "paymob_intention_failed", "تعذر تجهيز صفحة الدفع. أعد المحاولة بعد قليل.");
    }
    const attemptPayload = {
      attemptId,
      specialReference,
      intentionId: intention.id,
      amountCents: intention.amountCents,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await Promise.all([
      snap.ref.update({
        paymobCheckout: attemptPayload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      snap.ref.collection(CHECKOUT_ATTEMPTS).doc(attemptId).set(attemptPayload),
    ]);
    return {
      checkoutUrl: intention.checkoutUrl,
      publicKey: intention.publicKey,
      clientSecret: intention.clientSecret,
      amountCents: intention.amountCents,
      periodCode: quote.periodCode,
      remainingMonths: quote.remainingMonths,
    };
  });

export const previewSubscriptionQuote = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth || context.auth.token.firebase?.sign_in_provider === "anonymous") {
      fail("unauthenticated", "sign_in_required");
    }
    const body = (data || {}) as {
      companyUID?: unknown; organizationUID?: unknown; uids?: unknown; periodCode?: unknown;
    };
    const companyUID = str(body.companyUID);
    if (!companyUID) fail("invalid-argument", "company_required", "معرّف الشركة مطلوب.");
    const raw = Array.isArray(body.uids) ? body.uids : [];
    const uids = raw.map((v) => str(v)).filter(Boolean);
    if (uids.length === 0) fail("invalid-argument", "no_delegates", "اختر مندوباً واحداً على الأقل.");
    const db = admin.firestore();
    // Authz against a synthetic request in the same company.
    await assertCallerMayPay(db, context.auth.uid, {
      companyUID,
      organizationUID: str(body.organizationUID),
      supervisorUid: context.auth.uid,
    });
    try {
      const quote = await previewRenewalQuote(db, {
        companyUID,
        organizationUID: str(body.organizationUID),
        uids,
        periodCode: str(body.periodCode),
        at: new Date(),
      });
      return {
        amountCents: quote.amountCents,
        amount: quote.amount,
        periodCode: quote.periodCode,
        remainingMonths: quote.remainingMonths,
        delegateCount: quote.items.length,
      };
    } catch (e) {
      const reason = e instanceof QuoteError ? e.reason : "quote_failed";
      fail("failed-precondition", reason, quoteErrorMessage(reason));
    }
  });

export const reconcileSubscriptionPayments = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 120, memory: "256MB" as const})
  .https.onCall(async (_data, context) => {
    if (!context.auth || context.auth.token.firebase?.sign_in_provider === "anonymous") {
      fail("unauthenticated", "sign_in_required");
    }
    const db = admin.firestore();
    const snap = await db.collection("users").doc(context.auth.uid).get();
    const role = str(snap.get("role"));
    if (!RENEWAL_ROLES.has(role)) fail("permission-denied", "caller_not_allowed");
    const res = await expireAbandonedRenewals(db, new Date());
    return res;
  });

function quoteErrorMessage(reason: string): string {
  switch (reason) {
  case "already_paid":
    return "هذا الطلب مدفوع مسبقاً.";
  case "already_covered":
    return "أحد المناديب المحددين مغطى بالفعل في طلب آخر لنفس الفترة.";
  case "checkout_in_progress":
    return "جاري تجهيز الدفع. انتظر لحظات ثم أعد المحاولة.";
  case "expired":
    return "انتهت مهلة الدفع. يمكنك إعادة المحاولة على نفس الطلب.";
  case "free_period":
    return "لا حاجة للدفع خلال فترة العرض المجاني.";
  case "period_mismatch":
    return "فترة التجديد غير قابلة للدفع الآن.";
  default:
    return "تعذر تجهيز الدفع. أعد المحاولة.";
  }
}

export function requestIdFromPaymobObj(obj: Record<string, unknown>): string {
  return resolveRequestIdFromPaymobReference(paymobReferenceFromObj(obj));
}

export function isPaymobIntegrationAllowed(
  obj: Record<string, unknown>,
  integrationIds: number[],
): boolean {
  const integrationId = Number(obj.integration_id);
  return Number.isInteger(integrationId) && integrationId > 0 && integrationIds.includes(integrationId);
}

/** Company label on delegate_requests, else organizations/{org}/companies/{id}. */
export async function resolveCompanyNameFromRequest(
  db: admin.firestore.Firestore,
  data: Record<string, unknown>,
): Promise<string> {
  const fromReq = str(data.companyName) || str(data.company_name);
  if (fromReq) return fromReq;
  const companyUID = str(data.companyUID) || str(data.companyId);
  const orgUID = str(data.organizationUID) || str(data.organizationId);
  if (!companyUID || !orgUID) return "";
  const snap = await db.doc(`organizations/${orgUID}/companies/${companyUID}`).get();
  if (!snap.exists) return "";
  const company = snap.data() || {};
  return str(company.name) || str(company.companyName) || str(company.title) || "";
}

async function recordSupersededPayment(
  db: admin.firestore.Firestore,
  p: {
    txId: string;
    requestId: string;
    attemptId: string;
    paymobRef: string;
    paymobOrderId: string;
    amountCents: number;
    currency: string;
    paidAt: Date;
    companyUID: string;
    organizationUID: string;
    companyName?: string;
    messaging?: PaymobMessaging;
  },
): Promise<void> {
  const companyName = str(p.companyName);
  await db.collection(SUPERSEDED_PAYMENTS).doc(p.txId).set({
    requestId: p.requestId,
    attemptId: p.attemptId,
    paymobTransactionId: p.txId,
    paymobOrderId: p.paymobOrderId,
    paymobReference: p.paymobRef,
    amountCents: p.amountCents,
    currency: p.currency,
    needs_refund: true,
    companyUID: p.companyUID,
    organizationUID: p.organizationUID,
    ...(companyName ? {companyName} : {}),
    paidAt: admin.firestore.Timestamp.fromDate(p.paidAt),
    receivedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await notifyPaymobSupersededPaymentRefund(db, {
    requestId: p.requestId,
    attemptId: p.attemptId,
    txId: p.txId,
    amountCents: p.amountCents,
    currency: p.currency,
    companyUID: p.companyUID,
    organizationUID: p.organizationUID,
    companyName: p.companyName,
    messaging: p.messaging,
  });
  console.log(JSON.stringify({
    event: "paymob_superseded_payment",
    requestId: p.requestId,
    attemptId: p.attemptId,
    txId: p.txId,
    needs_refund: true,
  }));
}

export type PaymobAttemptRoute =
  | "apply"
  | "ignored_stale_attempt"
  | "rejected_foreign_attempt"
  | "superseded_needs_refund";

/**
 * Validates checkout attempt before any subscription payment write.
 * Legacy refs (bare requestId) bypass attempt checks.
 */
export async function routePaymobAttemptBeforeApply(
  db: admin.firestore.Firestore,
  p: {
    requestId: string;
    webhookAttemptId: string;
    success: boolean;
    paymobRef: string;
    txId: string;
    paymobOrderId: string;
    amountCents: number;
    currency: string;
    paidAt: Date;
    messaging?: PaymobMessaging;
  },
): Promise<PaymobAttemptRoute> {
  if (p.webhookAttemptId === "") return "apply";
  const reqRef = db.collection("delegate_requests").doc(p.requestId);
  const attemptRef = reqRef.collection(CHECKOUT_ATTEMPTS).doc(p.webhookAttemptId);
  const [reqSnap, attemptSnap] = await Promise.all([reqRef.get(), attemptRef.get()]);
  if (!reqSnap.exists || !attemptSnap.exists) {
    console.log(JSON.stringify({
      event: "paymob_webhook_rejected",
      reason: "foreign_attempt",
      requestId: p.requestId,
      attemptId: p.webhookAttemptId,
      txId: p.txId,
      requestExists: reqSnap.exists,
      attemptExists: attemptSnap.exists,
    }));
    return "rejected_foreign_attempt";
  }
  const checkout = (reqSnap.get("paymobCheckout") && typeof reqSnap.get("paymobCheckout") === "object")
    ? reqSnap.get("paymobCheckout") as Record<string, unknown>
    : {};
  const currentAttempt = str(checkout.attemptId);
  if (currentAttempt === p.webhookAttemptId) return "apply";
  if (p.success) {
    const data = (reqSnap.data() || {}) as Record<string, unknown>;
    const companyName = await resolveCompanyNameFromRequest(db, data);
    await recordSupersededPayment(db, {
      txId: p.txId,
      requestId: p.requestId,
      attemptId: p.webhookAttemptId,
      paymobRef: p.paymobRef,
      paymobOrderId: p.paymobOrderId,
      amountCents: p.amountCents,
      currency: p.currency,
      paidAt: p.paidAt,
      companyUID: str(data.companyUID) || str(data.companyId),
      organizationUID: str(data.organizationUID) || str(data.organizationId),
      companyName,
      messaging: p.messaging,
    });
    return "superseded_needs_refund";
  }
  return "ignored_stale_attempt";
}

export async function handlePaymobWebhook(opts: {
  obj: Record<string, unknown>;
  hmac: string;
  hmacSecret: string;
  db: admin.firestore.Firestore;
  integrationIds?: number[];
  messaging?: PaymobMessaging;
  now?: Date;
}): Promise<{status: number; outcome: string}> {
  if (!opts.obj || !verifyTransactionPostHmac(opts.obj, opts.hmac, opts.hmacSecret)) {
    return {status: 401, outcome: "invalid_hmac"};
  }
  const pending = boolFlag(opts.obj.pending);
  if (pending) return {status: 200, outcome: "ignored_pending"};
  if (opts.integrationIds?.length && !isPaymobIntegrationAllowed(opts.obj, opts.integrationIds)) {
    console.log(JSON.stringify({
      event: "paymob_webhook_rejected",
      reason: "integration_not_allowed",
      integrationId: opts.obj.integration_id,
    }));
    return {status: 200, outcome: "rejected_integration"};
  }
  const paymobRef = paymobReferenceFromObj(opts.obj);
  const requestId = resolveRequestIdFromPaymobReference(paymobRef);
  const webhookAttemptId = attemptIdFromPaymobReference(paymobRef);
  const txId = idStr(opts.obj.id);
  if (!requestId || !txId) return {status: 200, outcome: "ignored_incomplete"};
  const order = (opts.obj.order && typeof opts.obj.order === "object")
    ? opts.obj.order as Record<string, unknown>
    : {};
  const isVoided = boolFlag(opts.obj.is_voided);
  const isRefunded = boolFlag(opts.obj.is_refunded);
  const success = boolFlag(opts.obj.success) && !isVoided && !isRefunded;
  const amountCents = Number(opts.obj.amount_cents);
  const currency = str(opts.obj.currency) || "EGP";
  const paidAt = opts.now || new Date();
  const route = await routePaymobAttemptBeforeApply(opts.db, {
    requestId,
    webhookAttemptId,
    success,
    paymobRef,
    txId,
    paymobOrderId: idStr(order.id),
    amountCents: Number.isFinite(amountCents) ? amountCents : 0,
    currency,
    paidAt,
    messaging: opts.messaging,
  });
  if (route !== "apply") return {status: 200, outcome: route};
  const outcome = await applyVerifiedSubscriptionPayment(opts.db, {
    requestId,
    paymobTransactionId: txId,
    paymobOrderId: idStr(order.id),
    success,
    amountCents: Number.isFinite(amountCents) ? amountCents : 0,
    currency,
    paidAt,
    isVoided,
    isRefunded,
  });
  return {status: 200, outcome};
}

export const paymobSubscriptionWebhook = functions
  .region("us-central1")
  .runWith(opts)
  .https.onRequest(async (req, res) => {
    if (req.method === "GET") {
      res.status(200).send("ok");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).send("method_not_allowed");
      return;
    }
    const env = readPaymobEnv();
    if ("error" in env) {
      console.error(JSON.stringify({event: "paymob_webhook_misconfigured", reason: env.error}));
      res.status(503).json({error: env.error});
      return;
    }
    const body = (req.body && typeof req.body === "object") ? req.body as Record<string, unknown> : {};
    const obj = (body.obj && typeof body.obj === "object")
      ? body.obj as Record<string, unknown>
      : body;
    const hmac = str(req.query.hmac);
    try {
      const result = await handlePaymobWebhook({
        obj,
        hmac,
        hmacSecret: env.hmacSecret,
        integrationIds: env.integrationIds,
        db: admin.firestore(),
      });
      res.status(result.status).json({ok: result.status === 200, outcome: result.outcome});
    } catch (e) {
      console.error(JSON.stringify({event: "paymob_webhook_error"}));
      res.status(503).json({error: "apply_failed"});
    }
  });
