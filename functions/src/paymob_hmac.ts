import * as crypto from "crypto";

/**
 * Transaction Processed (POST) HMAC fields, in Paymob's documented order.
 * https://developers.paymob.com/paymob-docs/developers/webhook-callbacks-and-hmac/hmac/hmac-transaction-callback
 */
export const TRANSACTION_POST_HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
] as const;

function lookup(obj: Record<string, unknown>, path: string): unknown {
  const parts = path.split(".");
  let cur: unknown = obj;
  for (const p of parts) {
    if (cur === null || cur === undefined || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[p];
  }
  return cur;
}

/** Stringify a Paymob HMAC field the same way the official Node sample does. */
export function hmacFieldString(value: unknown): string {
  return String(value);
}

export function transactionPostHmacPayload(obj: Record<string, unknown>): string {
  return TRANSACTION_POST_HMAC_FIELDS.map((f) => hmacFieldString(lookup(obj, f))).join("");
}

export function computeTransactionPostHmac(obj: Record<string, unknown>, secret: string): string {
  return crypto.createHmac("sha512", secret).update(transactionPostHmacPayload(obj)).digest("hex");
}

/** Timing-safe compare of lowercase hex HMACs. Missing/wrong-length values are a mismatch. */
export function verifyTransactionPostHmac(
  obj: Record<string, unknown>,
  receivedHmac: string,
  secret: string,
): boolean {
  if (!secret) return false;
  const computed = computeTransactionPostHmac(obj, secret);
  const a = Buffer.from(computed, "utf8");
  const b = Buffer.from(String(receivedHmac || "").toLowerCase(), "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}
