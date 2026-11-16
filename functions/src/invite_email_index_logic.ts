/**
 * invite_email_index: maps lowercased invitee email → pending invite metadata.
 * Used by onInviteWritten and backfill scripts. Clients never write this collection.
 */
import {normalizeEmail} from "./staff_accounts_logic";

export const INVITE_EMAIL_INDEX_COLLECTION = "invite_email_index";

export function inviteEmailIndexDocId(email: unknown): string {
  return normalizeEmail(email);
}

export interface InviteEmailIndexPayload {
  inviteId: string;
  organizationUID: string;
  companyUID: string;
  role: string;
  status: string;
}

/** Build index payload from an invite doc, or null when email is missing. */
export function inviteEmailIndexFromInvite(
  inviteId: string,
  data: Record<string, unknown>,
): InviteEmailIndexPayload | null {
  const email = inviteEmailIndexDocId(data.email);
  if (!email) return null;
  const status = String(data.status ?? "");
  if (status !== "pending") return null;
  const org = String(data.organizationId ?? data.organizationUID ?? "");
  const co = String(data.companyId ?? data.companyUID ?? "");
  const role = String(data.roleToAssign ?? data.role ?? "");
  return {inviteId, organizationUID: org, companyUID: co, role, status: "pending"};
}

export function inviteEmailChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): {oldEmail: string; newEmail: string} {
  const oldEmail = before ? inviteEmailIndexDocId(before.email) : "";
  const newEmail = after ? inviteEmailIndexDocId(after.email) : "";
  return {oldEmail, newEmail};
}

export type PendingInviteRow = {inviteId: string; data: Record<string, unknown>};

function inviteSortTimeMs(data: Record<string, unknown>): number {
  for (const key of ["createdAt", "updatedAt", "invitedAt"]) {
    const v = data[key];
    if (v && typeof v === "object" && v !== null && "toMillis" in v) {
      const toMillis = (v as {toMillis?: () => number}).toMillis;
      if (typeof toMillis === "function") return toMillis.call(v);
    }
    if (typeof v === "number") return v;
    if (typeof v === "string") {
      const t = Date.parse(v);
      if (!Number.isNaN(t)) return t;
    }
  }
  return 0;
}

/** Deterministic winner: newest pending invite per normalized email (tie → inviteId). */
export function pickNewestPendingInvite(
  entries: PendingInviteRow[],
): PendingInviteRow | null {
  if (!entries.length) return null;
  return entries.slice().sort((a, b) => {
    const tb = inviteSortTimeMs(b.data);
    const ta = inviteSortTimeMs(a.data);
    if (tb !== ta) return tb - ta;
    return b.inviteId.localeCompare(a.inviteId);
  })[0]!;
}

/** Delete index only when it still points at the invite being retired. */
export function shouldDeleteInviteEmailIndexForInvite(
  indexInviteId: unknown,
  writingInviteId: string,
): boolean {
  return String(indexInviteId ?? "") === writingInviteId;
}