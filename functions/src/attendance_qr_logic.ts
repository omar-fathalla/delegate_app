/**
 * TAS-372: the printed branch QR, signed by the server, and the device
 * integrity mark of a check-in.
 *
 * User decision (27 Nov): a printed QR signed by the server with a version
 * number. The admin regenerates it from the branch screen (version + 1), so
 * the old printed QR of that branch stops working. No tablet, no QR that
 * changes every minute.
 *
 * QR content (JSON, what the admin prints):
 *   {type: "attendance", v: 2, branch, branchId, organizationUID, qrVersion, sig}
 * Old app versions read it as before (they only look at type/branch/
 * branchId/organizationUID), so the new QR works with them too.
 *
 * sig = base64url(HMAC-SHA256(key, "tashil-att-qr|2|<org>|<branchId>|<qrVersion>")),
 * key from Secret Manager (ATTENDANCE_QR_KEY). The branch doc keeps the
 * current `qrVersion`; it binds nothing by itself (the signature does).
 *
 * Transition: a QR without a signature (old JSON, or a branch name only) is
 * accepted and the record is marked `qrCheck: "legacy"`, unless the branch
 * already has a signed QR (`qrVersion` set: the admin printed the new one,
 * so the old print is void) or ATTENDANCE_LEGACY_QR=reject (after the forced
 * update).
 */
import * as crypto from "crypto";
import {Refusal, refuse} from "./attendance_callables_logic";

export const QR_FORMAT = 2;

/** Server-only fields of attendance_logs (the rules refuse them from clients). */
export const ATTENDANCE_SERVER_INTEGRITY_FIELDS = ["qrCheck", "qrVersion", "deviceIntegrity"] as const;

export type QrCheck = "signed" | "legacy" | "none";
export type DeviceIntegrity = "verified" | "replayed" | "missing";

export type QrReason = "qr_invalid" | "qr_old";

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function qrRefuse(reason: QrReason): Refusal {
  return refuse(reason);
}

/** The branch's current QR version (0 = no signed QR issued yet). */
export function branchQrVersion(branch: Record<string, unknown> | null | undefined): number {
  const v = (branch || {}).qrVersion;
  return typeof v === "number" && Number.isInteger(v) && v > 0 ? v : 0;
}

export function qrSigningInput(organizationUID: string, branchId: string, qrVersion: number): string {
  return `tashil-att-qr|${QR_FORMAT}|${organizationUID}|${branchId}|${qrVersion}`;
}

export function signQr(key: string, organizationUID: string, branchId: string, qrVersion: number): string {
  return crypto.createHmac("sha256", key)
    .update(qrSigningInput(organizationUID, branchId, qrVersion))
    .digest("base64url");
}

function safeEqual(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** What the admin prints. */
export function buildQrPayload(x: {
  key: string;
  organizationUID: string;
  branchId: string;
  branchName: string;
  qrVersion: number;
}): Record<string, unknown> {
  return {
    type: "attendance",
    v: QR_FORMAT,
    branch: x.branchName,
    branchId: x.branchId,
    organizationUID: x.organizationUID,
    qrVersion: x.qrVersion,
    sig: signQr(x.key, x.organizationUID, x.branchId, x.qrVersion),
  };
}

/** The QR the app scanned, as sent to delegateCheckIn (`qr`). */
export type QrProof =
  | {kind: "none"}
  | {kind: "legacy"}
  | {kind: "signed"; branchId: string; organizationUID: string; qrVersion: number; sig: string};

export function parseQrProof(raw: unknown): QrProof {
  if (!raw || typeof raw !== "object") return {kind: "none"};
  const d = raw as Record<string, unknown>;
  const sig = str(d.sig);
  if (!sig) return d.legacy === true ? {kind: "legacy"} : {kind: "none"};
  const v = d.qrVersion;
  return {
    kind: "signed",
    branchId: str(d.branchId),
    organizationUID: str(d.organizationUID),
    qrVersion: typeof v === "number" && Number.isInteger(v) ? v : -1,
    sig: sig.slice(0, 200),
  };
}

export interface QrDecisionInput {
  proof: QrProof;
  /** The branch the check-in names (already validated by parseCheckIn). */
  branchId: string;
  branchOrganizationUID: string;
  branch: Record<string, unknown> | null | undefined;
  key: string;
  /** "reject" after the forced update; anything else accepts legacy QRs. */
  legacyMode: string;
}

export type QrDecision = {ok: true; qrCheck: QrCheck; qrVersion?: number} | Refusal;

/** Checks the scanned QR against the branch (runs before the geofence). */
export function decideQr(x: QrDecisionInput): QrDecision {
  const current = branchQrVersion(x.branch);
  const p = x.proof;
  if (p.kind === "none") return {ok: true, qrCheck: "none"};
  if (p.kind === "legacy") {
    if (current > 0 || x.legacyMode === "reject") return qrRefuse("qr_old");
    return {ok: true, qrCheck: "legacy"};
  }
  if (!x.key) return qrRefuse("qr_invalid");
  if (p.branchId !== x.branchId || p.organizationUID !== x.branchOrganizationUID || p.qrVersion < 1) {
    return qrRefuse("qr_invalid");
  }
  if (!safeEqual(p.sig, signQr(x.key, p.organizationUID, p.branchId, p.qrVersion))) {
    return qrRefuse("qr_invalid");
  }
  if (p.qrVersion !== current) return qrRefuse("qr_old");
  return {ok: true, qrCheck: "signed", qrVersion: p.qrVersion};
}

/**
 * Device integrity from the App Check token of the call (Play Integrity on
 * Android, DeviceCheck/App Attest on iOS). The app sends a limited-use token
 * and the callable consumes it, so a replayed token is marked too. Only
 * marked, never refused, until enforcement after the forced update.
 */
export function deviceIntegrityOf(app: {alreadyConsumed?: boolean} | null | undefined): DeviceIntegrity {
  if (!app) return "missing";
  return app.alreadyConsumed ? "replayed" : "verified";
}

/** Global staff, or the branch's own chain admin (same as the branch rules). */
export function mayManageBranchQr(token: Record<string, unknown> | null | undefined, canonRole: string,
  branchOrganizationUID: string): boolean {
  if (canonRole === "super-admin" || canonRole === "technical_support") return true;
  if (canonRole !== "organization-admin") return false;
  const t = token || {};
  const org = str(t.orgId) || str(t.organizationId);
  return !!org && org === branchOrganizationUID;
}
