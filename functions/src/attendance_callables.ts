/**
 * delegateCheckIn / delegateCheckOut (TAS-361 phase 2)
 *
 * The server side of attendance. The app sends the branch id and its position;
 * the server re-reads the branch, the delegate's membership and its latest
 * records, runs every check (attendance_callables_logic.ts) inside a
 * transaction, and writes attendance_logs. Check-in refusals come back as
 * `failed-precondition` with details {reason, message, distanceMeters?,
 * allowedMeters?, branchName?}; the app shows `message`.
 *
 * A check-out is never refused for the distance: it is written and flagged
 * (checkOutOutsideBranch) for HR. Forgotten sessions are not closed here
 * (TAS-362).
 *
 * Idempotent: the check-in id is the app's requestId, the check-out id is
 * `${attendanceId}_out`, so a retry after a timeout never writes twice.
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:delegateCheckIn,
 *   functions:tashil-mobile-notifications:delegateCheckOut
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import {callerDelegateId, callerSelfIds} from "./caller_delegate_id";
import {
  CheckInInput,
  Doc,
  Refusal,
  RecentLog,
  buildCheckInDoc,
  checkOutDistance,
  decideCheckIn,
  decideCheckOut,
  parseCheckIn,
  parseCheckOut,
  refuse,
  toRecentLog,
} from "./attendance_callables_logic";
import {
  branchQrVersion,
  buildQrPayload,
  decideQr,
  deviceIntegrityOf,
  mayManageBranchQr,
  parseQrProof,
} from "./attendance_qr_logic";
import {canonicalStaffRole} from "./staff_claims_sync_logic";

if (admin.apps.length === 0) admin.initializeApp();

const RECENT_LIMIT = 20;

/**
 * TAS-372: HMAC key of the printed branch QR (Secret Manager). Must exist on
 * the project before deploy:
 *   firebase functions:secrets:set ATTENDANCE_QR_KEY --project <project>
 */
export const ATTENDANCE_QR_KEY = defineSecret("ATTENDANCE_QR_KEY");

/** "reject" after the forced update; default accepts unsigned (legacy) QRs. */
function legacyQrMode(): string {
  return String(process.env.ATTENDANCE_LEGACY_QR || "accept").trim().toLowerCase();
}

function qrKey(): string {
  try {
    return ATTENDANCE_QR_KEY.value() || "";
  } catch {
    return "";
  }
}

function isRefusal(x: unknown): x is Refusal {
  return !!x && typeof x === "object" && (x as {ok?: unknown}).ok === false;
}

function fail(r: Refusal, code: functions.https.FunctionsErrorCode = "failed-precondition"): never {
  throw new functions.https.HttpsError(code, r.message, {
    reason: r.reason,
    message: r.message,
    ...(r.distanceMeters != null ? {distanceMeters: r.distanceMeters} : {}),
    ...(r.allowedMeters != null ? {allowedMeters: r.allowedMeters} : {}),
    ...(r.branchName ? {branchName: r.branchName} : {}),
  });
}

function toMs(v: unknown): number | null {
  if (v instanceof admin.firestore.Timestamp) return v.toMillis();
  return null;
}

async function loadBranch(db: FirebaseFirestore.Firestore, input: {branchId: string; branchOrganizationUID: string}): Promise<Doc> {
  if (!input.branchId) return null;
  const nested = await db.collection("organizations").doc(input.branchOrganizationUID)
    .collection("branches").doc(input.branchId).get();
  if (nested.exists) return nested.data() || {};
  // Root branches are written by staff only (TAS-54).
  const root = await db.collection("branches").doc(input.branchId).get();
  return root.exists ? (root.data() || {}) : null;
}

function requireAuth(context: functions.https.CallableContext): Record<string, unknown> {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "سجّل دخول الأول.");
  }
  return (context.auth.token || {}) as Record<string, unknown>;
}

/** The caller's latest records, read inside the transaction (no stale cache). */
async function recentLogs(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  ids: string[],
): Promise<RecentLog[]> {
  const all: RecentLog[] = [];
  for (const id of ids) {
    const snap = await tx.get(db.collection("attendance_logs")
      .where("delegateId", "==", id).orderBy("timestamp", "desc").limit(RECENT_LIMIT));
    snap.docs.forEach((d) => all.push(toRecentLog(d.id, d.data(), toMs)));
  }
  return all;
}

export const delegateCheckIn = functions
  .region("us-central1")
  // TAS-372: the app sends a limited-use App Check token; consuming it marks
  // a replay. Not enforced (monitoring) until the forced update.
  .runWith({secrets: [ATTENDANCE_QR_KEY], consumeAppCheckToken: true})
  .https.onCall(async (data: unknown, context) => {
    const token = requireAuth(context);
    const parsed = parseCheckIn(data);
    if (isRefusal(parsed)) fail(parsed, "invalid-argument");
    const input = parsed as CheckInInput;
    const delegateId = callerDelegateId(context.auth?.uid, token);
    const selfIds = callerSelfIds(context.auth?.uid, token);
    const db = admin.firestore();

    const [branch, membershipSnap] = await Promise.all([
      loadBranch(db, input),
      db.collection("organizations").doc(input.organizationId)
        .collection("companies").doc(input.companyId)
        .collection("delegates").doc(delegateId).get(),
    ]);
    const membership = membershipSnap.exists ? (membershipSnap.data() || {}) : null;
    const ref = db.collection("attendance_logs").doc(input.requestId);

    // TAS-372: the scanned QR (signature + current version of the branch).
    const qr = decideQr({
      proof: parseQrProof(input.qr),
      branchId: input.branchId,
      branchOrganizationUID: input.branchOrganizationUID,
      branch,
      key: qrKey(),
      legacyMode: legacyQrMode(),
    });
    if (isRefusal(qr)) {
      functions.logger.info("delegateCheckIn: QR refused", {delegateId, reason: qr.reason,
        branchId: input.branchId});
      fail(qr);
    }
    const deviceIntegrity = deviceIntegrityOf(context.app);

    const result = await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists) {
        const e = existing.data() || {};
        // A retry of a check-in that already landed.
        if (selfIds.includes(String(e.delegateId || "")) && e.type === "check_in") {
          return {ok: true as const, already: true, distanceMeters: null as number | null};
        }
        return refuse("bad_request");
      }
      const recent = await recentLogs(tx, db, selfIds);
      const decision = decideCheckIn({input, token, membership, branch, recent, nowMs: Date.now()});
      if (!decision.ok) return decision;
      tx.create(ref, {
        ...buildCheckInDoc(input, delegateId),
        // TAS-372: server-only marks (the rules refuse them from clients).
        qrCheck: qr.qrCheck,
        ...(qr.qrVersion != null ? {qrVersion: qr.qrVersion} : {}),
        deviceIntegrity,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {ok: true as const, already: false, distanceMeters: decision.distanceMeters};
    });

    if (isRefusal(result)) {
      functions.logger.info("delegateCheckIn: refused", {delegateId, reason: result.reason,
        distance: result.distanceMeters});
      fail(result);
    }
    return {ok: true, attendanceId: ref.id, already: result.already, distanceMeters: result.distanceMeters};
  });

/** The branch doc ref (nested under its chain first, then root). */
async function branchRef(db: FirebaseFirestore.Firestore, org: string, branchId: string):
  Promise<FirebaseFirestore.DocumentReference | null> {
  const nested = db.collection("organizations").doc(org).collection("branches").doc(branchId);
  if ((await nested.get()).exists) return nested;
  const root = db.collection("branches").doc(branchId);
  const snap = await root.get();
  if (!snap.exists) return null;
  const rootOrg = String((snap.data() || {}).organizationUID || "").trim();
  return !rootOrg || rootOrg === org ? root : null;
}

/**
 * TAS-372: the signed QR of a branch, for the admin to print.
 *
 * {branchId, organizationUID, regenerate?: boolean}
 * - regenerate false: returns the current signed QR, or {qr: null} when the
 *   branch has none yet (the screen then shows the old QR and a button).
 * - regenerate true: qrVersion + 1 (transaction), so every QR printed before
 *   is refused by delegateCheckIn ("qr_old").
 * Allowed: super-admin, technical support, or this chain's org admin (the
 * same people the rules let edit the branch).
 */
export const branchAttendanceQr = functions
  .region("us-central1")
  .runWith({secrets: [ATTENDANCE_QR_KEY]})
  .https.onCall(async (data: unknown, context) => {
    const token = requireAuth(context);
    const d = (data && typeof data === "object") ? data as Record<string, unknown> : {};
    const branchId = typeof d.branchId === "string" ? d.branchId.trim() : "";
    const org = typeof d.organizationUID === "string" ? d.organizationUID.trim() : "";
    if (!branchId || !org) {
      throw new functions.https.HttpsError("invalid-argument", "الفرع مش محدد.");
    }
    if (!mayManageBranchQr(token, canonicalStaffRole(token.role), org)) {
      throw new functions.https.HttpsError("permission-denied", "مش مسموحلك تعمل كود حضور للفرع ده.");
    }
    const key = qrKey();
    if (!key) {
      functions.logger.error("branchAttendanceQr: ATTENDANCE_QR_KEY is not set");
      throw new functions.https.HttpsError("failed-precondition", "كود الحضور الموقّع مش متاح دلوقتي.");
    }
    const db = admin.firestore();
    const ref = await branchRef(db, org, branchId);
    if (!ref) throw new functions.https.HttpsError("not-found", "الفرع ده مش موجود.");

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const b = snap.data() || {};
      let version = branchQrVersion(b);
      if (d.regenerate === true) {
        version += 1;
        tx.update(ref, {
          qrVersion: version,
          qrUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          qrUpdatedBy: context.auth?.uid || "",
        });
      }
      const name = String(b.branchName || b.name || "").trim();
      return {version, name};
    });

    if (d.regenerate === true) {
      functions.logger.info("branchAttendanceQr: regenerated", {branchId, org, version: result.version,
        by: context.auth?.uid});
    }
    if (result.version < 1) return {qr: null, qrVersion: 0};
    return {
      qrVersion: result.version,
      qr: buildQrPayload({key, organizationUID: org, branchId, branchName: result.name,
        qrVersion: result.version}),
    };
  });

export const delegateCheckOut = functions
  .region("us-central1")
  .https.onCall(async (data: unknown, context) => {
    const token = requireAuth(context);
    const parsed = parseCheckOut(data);
    if (isRefusal(parsed)) fail(parsed, "invalid-argument");
    const input = parsed as {attendanceId: string; lat: number | null; lng: number | null};
    const selfIds = callerSelfIds(context.auth?.uid, token);
    const db = admin.firestore();
    const inRef = db.collection("attendance_logs").doc(input.attendanceId);
    const outRef = db.collection("attendance_logs").doc(`${input.attendanceId}_out`);

    // The branch of the record (read once before the transaction).
    const first = await inRef.get();
    const rec = first.data() || {};
    const branch = await loadBranch(db, {
      branchId: String(rec.branchId || ""),
      branchOrganizationUID: String(rec.branchOrganizationUID || rec.organizationId || ""),
    });
    const dist = checkOutDistance(input.lat, input.lng, branch);

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(inRef);
      const record = snap.exists ? (snap.data() || {}) : null;
      const decision = decideCheckOut({attendanceId: input.attendanceId, record, selfIds, token});
      if (!decision.ok) return decision;
      if (decision.already) return {ok: true as const, already: true};
      const r = record as Record<string, unknown>;
      const now = admin.firestore.FieldValue.serverTimestamp();
      const location = {latitude: input.lat, longitude: input.lng};
      const outDoc: Record<string, unknown> = {
        delegateId: r.delegateId ?? r.userId,
        userId: r.userId ?? r.delegateId,
        companyId: r.companyId,
        organizationId: r.organizationId,
        timestamp: now,
        type: "check_out",
        location,
        relatedCheckInId: input.attendanceId,
        source: "server",
      };
      for (const k of ["branchName", "branchId", "branchOrganizationUID"]) {
        if (r[k] != null) outDoc[k] = r[k];
      }
      tx.set(outRef, outDoc);
      tx.update(inRef, {
        checkOutTime: now,
        checkOutLocation: location,
        checkOutDocId: outRef.id,
      });
      return {ok: true as const, already: false};
    });

    if (isRefusal(result)) fail(result);
    if (dist.outside) {
      functions.logger.info("delegateCheckOut: outside the branch", {
        attendanceId: input.attendanceId, distance: dist.distanceMeters,
      });
    }
    return {ok: true, already: result.already, outsideBranch: dist.outside, distanceMeters: dist.distanceMeters};
  });
