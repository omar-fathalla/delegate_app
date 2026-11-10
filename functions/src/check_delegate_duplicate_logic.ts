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
