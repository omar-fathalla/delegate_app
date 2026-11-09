import {createHash, randomBytes} from "crypto";

/** Our own password-setup tokens (7 days, single use). Only the hash is stored. */
export const SETUP_TOKEN_COLLECTION = "password_setup_tokens";
export const SETUP_TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export const MIN_PASSWORD_LENGTH = 8;

export function newSetupToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashSetupToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function isWellFormedToken(token: unknown): token is string {
  return typeof token === "string" && /^[A-Za-z0-9_-]{40,64}$/.test(token);
}

export type TokenState = "ok" | "missing" | "used" | "expired";

export function tokenState(
  doc: {usedAtMs?: number | null; expiresAtMs?: number | null} | null,
  nowMs: number,
): TokenState {
  if (!doc) return "missing";
  if (doc.usedAtMs) return "used";
  if (!doc.expiresAtMs || doc.expiresAtMs <= nowMs) return "expired";
  return "ok";
}

export function buildSetupLink(pageUrl: string, token: string): string {
  const dst = new URL(pageUrl);
  if (dst.protocol !== "https:" && !/^(127\.0\.0\.1|localhost)$/.test(dst.hostname)) throw new Error("unsafe_page_url");
  dst.searchParams.set("t", token);
  return dst.toString();
}

export function passwordProblem(pw: unknown): string | null {
  if (typeof pw !== "string") return "invalid";
  if (pw.length < MIN_PASSWORD_LENGTH) return "too_short";
  if (pw.length > 128) return "too_long";
  return null;
}
