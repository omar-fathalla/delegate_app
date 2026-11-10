/** Cross-company national ID / phone uniqueness. A delegate belongs to one company only. */

export type DuplicateReason = "same_company" | "another_company";
export type DuplicateField = "nationalId" | "phoneNumber";

export interface DuplicateHit {
  companyUID: string;
  companyName: string;
  field: DuplicateField;
}

export interface DuplicateDecision {
  duplicate: boolean;
  reason?: DuplicateReason;
  /** Other company's display name only. Never set for same_company. */
  companyName?: string;
  field?: DuplicateField;
}

const ARABIC_INDIC = /[\u0660-\u0669]/g;
const EXTENDED_ARABIC_INDIC = /[\u06F0-\u06F9]/g;

export function normalizeIdDigits(raw: string): string {
  return raw
    .trim()
    .replace(ARABIC_INDIC, (ch) => String(ch.charCodeAt(0) - 0x0660))
    .replace(EXTENDED_ARABIC_INDIC, (ch) => String(ch.charCodeAt(0) - 0x06F0))
    .replace(/\s+/g, "");
}

export function isOpenRequestStatus(status: unknown): boolean {
  const s = String(status || "").toLowerCase();
  return s === "pending" || s === "approved";
}

export function isExistingDelegateStatus(status: unknown): boolean {
  const s = String(status || "").toLowerCase();
  return s !== "inactive";
}

export function decideDuplicate(
  callerCompanyUID: string,
  hits: DuplicateHit[],
): DuplicateDecision {
  const caller = callerCompanyUID.trim();
  if (!hits.length || !caller) return {duplicate: false};
  const same = hits.find((h) => h.companyUID === caller);
  if (same) {
    return {duplicate: true, reason: "same_company", field: same.field};
  }
  const other = hits[0];
  const name = (other.companyName || "").trim();
  return {
    duplicate: true,
    reason: "another_company",
    field: other.field,
    ...(name ? {companyName: name} : {}),
  };
}

/** Public payload: boolean, reason, and the other company NAME only. */
export function publicDuplicateResult(decision: DuplicateDecision): {
  duplicate: boolean;
  reason?: DuplicateReason;
  companyName?: string;
} {
  if (!decision.duplicate) return {duplicate: false};
  if (decision.reason === "another_company") {
    return {
      duplicate: true,
      reason: "another_company",
      ...(decision.companyName ? {companyName: decision.companyName} : {}),
    };
  }
  return {duplicate: true, reason: "same_company"};
}

/** Strip separators and fold +20 / 0020 / 20 prefixes to 01xxxxxxxxx. */
export function normalizeEgyptianPhone(raw: string): string {
  let s = normalizeIdDigits(raw).replace(/[^\d]/g, "");
  if (s.startsWith("0020")) s = s.slice(4);
  else if (s.startsWith("20") && s.length >= 12) s = s.slice(2);
  if (s.startsWith("1") && s.length === 10) s = "0" + s;
  return s;
}

/** Unique query values covering how phones are stored on legacy docs. */
export function phoneQueryVariants(raw: string): string[] {
  const local = normalizeEgyptianPhone(raw);
  if (!local) return [];
  const out = new Set<string>([local]);
  if (local.startsWith("01") && local.length === 11) {
    const rest = local.slice(1);
    out.add("20" + rest);
    out.add("+20" + rest);
    out.add("0020" + rest);
    out.add(rest);
  }
  out.add(normalizeIdDigits(raw).replace(/[^\d+]/g, ""));
  return [...out].filter(Boolean);
}
