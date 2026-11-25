/**
 * Pure helpers for createSupervisorPenalty (TAS-320).
 *
 * User decision 2026-11-24: a supervisor (a delegate whose position is
 * Supervisor, signed in with a delegate token) may record a penalty on a
 * delegate of its own company. The penalty is issued at once (status ISSUED,
 * no branches-marketing / general-manager approval) and is deducted from that
 * month's payroll.
 */
import {SUPERVISOR_POSITIONS} from "./supervisor_cards_logic";

export const PENALTY_CATEGORIES = [
  "UNAUTHORIZED_PHOTOGRAPHY", "DATA_MISSING", "THEFT", "PROTOCOL_BREACH", "OTHER",
];
export const MAX_FINE = 10000;

const INACTIVE = ["deleted", "rejected", "removed"];

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export interface PenaltyInput {
  targetDelegateId: string;
  title: string;
  category: string;
  incidentDescription: string;
  fineAmount: number;
  branchId: string;
  branchName: string;
}

/** Validates the request body. Returns an error message or the clean input. */
export function parsePenaltyInput(data: unknown): {error: string} | PenaltyInput {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const targetDelegateId = str(d.targetDelegateId);
  if (!targetDelegateId || targetDelegateId.includes("/")) return {error: "targetDelegateId مطلوب."};
  const title = str(d.title);
  if (title.length < 2 || title.length > 120) return {error: "عنوان الجزاء مطلوب (من 2 لـ 120 حرف)."};
  const category = str(d.category).toUpperCase() || "OTHER";
  if (!PENALTY_CATEGORIES.includes(category)) return {error: "نوع المخالفة غير صحيح."};
  const incidentDescription = str(d.incidentDescription);
  if (incidentDescription.length > 1000) return {error: "الوصف طويل جداً."};
  const fineAmount = Number(d.fineAmount);
  if (!Number.isFinite(fineAmount) || fineAmount <= 0 || fineAmount > MAX_FINE) {
    return {error: `قيمة الجزاء لازم تكون أكبر من صفر ولا تزيد عن ${MAX_FINE} ج.م.`};
  }
  return {
    targetDelegateId, title, category, incidentDescription,
    fineAmount: Math.round(fineAmount * 100) / 100,
    branchId: str(d.branchId), branchName: str(d.branchName),
  };
}

export function isSupervisorPosition(position: unknown): boolean {
  return SUPERVISOR_POSITIONS.includes(str(position));
}

export function isActiveDelegate(data: Record<string, unknown> | undefined): boolean {
  if (!data) return false;
  return !INACTIVE.includes(str(data.status).toLowerCase());
}

/** Which delegate ids the token may act as (its uid plus the delegateIds claim). */
export function callerDelegateIds(uid: string, token: Record<string, unknown> | undefined): string[] {
  const ids = [uid];
  // TAS-28 phase 0: the delegateId claim names the caller too.
  if (typeof token?.delegateId === "string" && token.delegateId.trim()) ids.push(token.delegateId.trim());
  const claim = token?.delegateIds;
  if (Array.isArray(claim)) for (const x of claim) if (typeof x === "string" && x.trim()) ids.push(x.trim());
  return [...new Set(ids.filter(Boolean))];
}

/** The penalty document, same shape as the app's PenaltyModel.toJson. Timestamps added by the caller. */
export function buildPenaltyDoc(args: {
  input: PenaltyInput;
  organizationUID: string;
  companyUID: string;
  companyName: string;
  supervisorId: string;
  supervisorName: string;
  supervisorPhone: string;
  targetName: string;
}): Record<string, unknown> {
  const {input} = args;
  return {
    companyId: args.companyUID,
    companyUID: args.companyUID,
    companyName: args.companyName,
    organizationId: args.organizationUID,
    organizationUID: args.organizationUID,
    ...(input.branchId ? {branchId: input.branchId} : {}),
    ...(input.branchName ? {branchName: input.branchName} : {}),
    createdById: args.supervisorId,
    createdByName: args.supervisorName,
    ...(args.supervisorPhone ? {createdByPhone: args.supervisorPhone} : {}),
    createdByRole: "supervisor_delegate",
    createdVia: "createSupervisorPenalty",
    title: input.title,
    category: input.category,
    incidentDescription: input.incidentDescription,
    fineAmount: input.fineAmount,
    currency: "EGP",
    status: "ISSUED",
    evidenceFiles: [],
    targetDelegateId: input.targetDelegateId,
    targetDelegateName: args.targetName,
    isRepeated: false,
    isConfidential: false,
  };
}
