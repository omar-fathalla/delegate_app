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
 * Offline records (TAS-363): the app saves a check-in / check-out on the
 * phone without network and sends it later with `offline: true`,
 * `capturedAtMs`, `timeTrusted`, `syncedAtMs`. The same checks run at the
 * captured time; hours count right away (user decision 27 Nov) from the
 * captured time when it is trusted and inside the limits
 * (decideOfflineTime), otherwise from the time the record reached the server
 * (HR can adjust). The record is flagged `offlineCheckIn` / `offlineCheckOut`
 * for HR review, never refused for its time.
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:delegateCheckIn,
 *   functions:tashil-mobile-notifications:delegateCheckOut
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {callerDelegateId, callerSelfIds} from "./caller_delegate_id";
import {
  CheckInInput,
  Doc,
  Refusal,
  RecentLog,
  CheckOutInput,
  OfflineTime,
  buildCheckInDoc,
  checkOutDistance,
  decideCheckIn,
  decideCheckOut,
  decideOfflineTime,
  lastRecordEndMs,
  offlineFields,
  parseCheckIn,
  parseCheckOut,
  refuse,
  toRecentLog,
} from "./attendance_callables_logic";

if (admin.apps.length === 0) admin.initializeApp();

const RECENT_LIMIT = 20;

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

    const result = await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists) {
        const e = existing.data() || {};
        // A retry of a check-in that already landed.
        if (selfIds.includes(String(e.delegateId || "")) && e.type === "check_in") {
          return {ok: true as const, already: true, distanceMeters: null as number | null,
            offline: null as OfflineTime | null};
        }
        return refuse("bad_request");
      }
      const recent = await recentLogs(tx, db, selfIds);
      const nowMs = Date.now();
      const offline: OfflineTime | null = input.offline ?
        decideOfflineTime(input.offline, nowMs, lastRecordEndMs(recent)) : null;
      const decision = decideCheckIn({input, token, membership, branch, recent, nowMs: offline ? offline.atMs : nowMs});
      if (!decision.ok) return decision;
      const serverNow = admin.firestore.FieldValue.serverTimestamp();
      tx.create(ref, {
        ...buildCheckInDoc(input, delegateId),
        timestamp: offline?.trusted ? admin.firestore.Timestamp.fromMillis(offline.atMs) : serverNow,
        ...(input.offline && offline ? {
          offlineCheckIn: true,
          receivedAt: serverNow,
          ...offlineFields("", input.offline, offline, (ms) => admin.firestore.Timestamp.fromMillis(ms)),
        } : {}),
      });
      return {ok: true as const, already: false, distanceMeters: decision.distanceMeters, offline};
    });

    if (isRefusal(result)) {
      functions.logger.info("delegateCheckIn: refused", {delegateId, reason: result.reason,
        distance: result.distanceMeters});
      fail(result);
    }
    return {
      ok: true,
      attendanceId: ref.id,
      already: result.already,
      distanceMeters: result.distanceMeters,
      ...(result.offline ? {timeTrusted: result.offline.trusted, countedFromMs: result.offline.atMs} : {}),
    };
  });

export const delegateCheckOut = functions
  .region("us-central1")
  .https.onCall(async (data: unknown, context) => {
    const token = requireAuth(context);
    const parsed = parseCheckOut(data);
    if (isRefusal(parsed)) fail(parsed, "invalid-argument");
    const input = parsed as CheckOutInput;
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
      const serverNow = admin.firestore.FieldValue.serverTimestamp();
      // TAS-363: an offline check-out counts from its captured time when
      // trusted and after the check-in, else from now.
      const offline: OfflineTime | null = input.offline ?
        decideOfflineTime(input.offline, Date.now(), toMs(r.timestamp)) : null;
      const now = offline?.trusted ? admin.firestore.Timestamp.fromMillis(offline.atMs) : serverNow;
      const ts = (ms: number) => admin.firestore.Timestamp.fromMillis(ms);
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
      const inUpdate: Record<string, unknown> = {
        checkOutTime: now,
        checkOutLocation: location,
        checkOutDocId: outRef.id,
      };
      if (input.offline && offline) {
        Object.assign(outDoc, {offlineCheckOut: true, receivedAt: serverNow},
          offlineFields("", input.offline, offline, ts));
        Object.assign(inUpdate, {offlineCheckOut: true, checkOutReceivedAt: serverNow},
          offlineFields("checkOut", input.offline, offline, ts));
      }
      tx.set(outRef, outDoc);
      tx.update(inRef, inUpdate as FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>);
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
