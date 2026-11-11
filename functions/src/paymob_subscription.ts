/**
 * Paymob test-mode checkout and webhook for one subscription renewal
 * (or registration) payment. The amount comes from quoteSubscriptionRequest;
 * the client never sends an amount or holds Paymob keys.
 *
 * Deploy (tashil-dev only, named):
 *   functions:tashil-mobile-notifications:createSubscriptionCheckout
 *   functions:tashil-mobile-notifications:paymobSubscriptionWebhook
 * Never deploy suspendExpiredSubscriptions with these. Test-mode keys only
 * (sk_test_ / pk_test_). Live keys are refused.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {QuoteError, applyVerifiedSubscriptionPayment, quoteSubscriptionRequest} from "./subscription_jobs";
import {verifyTransactionPostHmac} from "./paymob_hmac";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 60, memory: "256MB" as const};
const EGYPT_BASE = "https://accept.paymob.com";
const WEBHOOK_NAME = "paymobSubscriptionWebhook";

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
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
  if (secretKey.startsWith("sk_live_") || publicKey.startsWith("pk_live_")) {
    return {error: "paymob_live_forbidden"};
  }
  if (!secretKey.startsWith("sk_test_") || !publicKey.startsWith("pk_test_")) {
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
    console.error(JSON.stringify({event: "paymob_intention_failed", status: res.status}));
    throw new Error("paymob_intention_failed");
  }
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new Error("paymob_intention_failed");
  }
  const clientSecret = str(data.client_secret);
  const id = str(data.id);
  if (!clientSecret || !id) throw new Error("paymob_intention_failed");
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
    const env = readPaymobEnv();
    if ("error" in env) {
      const msg = env.error === "paymob_live_forbidden" || env.error === "paymob_test_keys_required"
        ? "دفع Paymob على بيئة الاختبار فقط. مفاتيح الإنتاج مرفوضة."
        : "تم حفظ الطلب بانتظار الدفع، لكن دفع Paymob غير مضبوط على الخادم بعد.";
      fail("failed-precondition", env.error, msg);
    }
    const db = admin.firestore();
    const snap = await db.collection("delegate_requests").doc(requestId).get();
    if (!snap.exists) fail("not-found", "not_found", "طلب التجديد غير موجود.");
    const req = (snap.data() || {}) as Record<string, unknown>;
    await assertCallerMayPay(db, context.auth.uid, req);
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
    const intention = await createPaymobIntention({
      env,
      amountCents: quote.amountCents,
      specialReference: requestId,
      notificationUrl: webhookUrl(projectId),
      billing: billingFromRequest(req, context.auth.uid),
      itemName: `تجديد ${quote.periodCode}`,
      itemCount: uids || 1,
    });
    await snap.ref.update({
      paymobCheckout: {
        intentionId: intention.id,
        amountCents: intention.amountCents,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      checkoutUrl: intention.checkoutUrl,
      publicKey: intention.publicKey,
      clientSecret: intention.clientSecret,
      amountCents: intention.amountCents,
      periodCode: quote.periodCode,
      remainingMonths: quote.remainingMonths,
    };
  });

function quoteErrorMessage(reason: string): string {
  switch (reason) {
  case "already_paid":
    return "هذا الطلب مدفوع مسبقاً.";
  case "already_covered":
    return "أحد المناديب المحددين مغطى بالفعل في طلب آخر لنفس الفترة.";
  case "expired":
    return "انتهت صلاحية عرض السعر. أنشئ طلب تجديد جديد.";
  case "free_period":
    return "لا حاجة للدفع خلال فترة العرض المجاني.";
  case "period_mismatch":
    return "فترة التجديد غير قابلة للدفع الآن.";
  default:
    return "تعذر تجهيز الدفع. أعد المحاولة.";
  }
}

export function requestIdFromPaymobObj(obj: Record<string, unknown>): string {
  const order = (obj.order && typeof obj.order === "object")
    ? obj.order as Record<string, unknown>
    : {};
  return str(order.merchant_order_id) || str(obj.merchant_order_id) ||
    str(obj.special_reference) || str(order.special_reference);
}

export async function handlePaymobWebhook(opts: {
  obj: Record<string, unknown>;
  hmac: string;
  hmacSecret: string;
  db: admin.firestore.Firestore;
  now?: Date;
}): Promise<{status: number; outcome: string}> {
  if (!opts.obj || !verifyTransactionPostHmac(opts.obj, opts.hmac, opts.hmacSecret)) {
    return {status: 401, outcome: "invalid_hmac"};
  }
  const pending = opts.obj.pending === true || String(opts.obj.pending) === "true";
  if (pending) return {status: 200, outcome: "ignored_pending"};
  const requestId = requestIdFromPaymobObj(opts.obj);
  const txId = str(opts.obj.id);
  if (!requestId || !txId) return {status: 200, outcome: "ignored_incomplete"};
  const order = (opts.obj.order && typeof opts.obj.order === "object")
    ? opts.obj.order as Record<string, unknown>
    : {};
  const success = opts.obj.success === true || String(opts.obj.success) === "true";
  const amountCents = Number(opts.obj.amount_cents);
  const currency = str(opts.obj.currency) || "EGP";
  const paidAt = opts.now || new Date();
  const outcome = await applyVerifiedSubscriptionPayment(opts.db, {
    requestId,
    paymobTransactionId: txId,
    paymobOrderId: str(order.id),
    success,
    amountCents: Number.isFinite(amountCents) ? amountCents : 0,
    currency,
    paidAt,
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
        db: admin.firestore(),
      });
      res.status(result.status).json({ok: result.status === 200, outcome: result.outcome});
    } catch (e) {
      console.error(JSON.stringify({event: "paymob_webhook_error"}));
      res.status(503).json({error: "apply_failed"});
    }
  });
