/**
 * Callable ensureStorageUploadIntent. Creates or reuses the immutable
 * storage_upload_intents/{folderId} doc after verifying the folder's
 * owning company (request or delegate). Clients cannot mint intents.
 *
 * Deploy: functions:ensureStorageUploadIntent --project tashil-dev
 * Do not deploy suspendExpiredSubscriptions with this function.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  decideEnsureIntent,
  isValidFolderId,
  normalizeFolderId,
  resolveOwningCompany,
  type OwnerHit,
} from "./storage_upload_intent_logic";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 30, memory: "256MB" as const};

function fail(code: functions.https.FunctionsErrorCode, reason: string): never {
  throw new functions.https.HttpsError(code, reason, {reason});
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function companyOf(data: FirebaseFirestore.DocumentData | undefined): string {
  if (!data) return "";
  return str(data.companyUID) || str(data.companyId);
}

async function loadHits(
  db: FirebaseFirestore.Firestore,
  folderId: string,
): Promise<OwnerHit[]> {
  const hits: OwnerHit[] = [];
  const intent = await db.collection("storage_upload_intents").doc(folderId).get();
  if (intent.exists) {
    const co = companyOf(intent.data());
    if (co) hits.push({source: "intent", companyUID: co});
  }
  const request = await db.collection("delegate_requests").doc(folderId).get();
  if (request.exists) {
    const co = companyOf(request.data());
    if (co) hits.push({source: "request", companyUID: co});
  }
  const delegates = await db.collectionGroup("delegates").where("uid", "==", folderId).limit(10).get();
  for (const doc of delegates.docs) {
    const fromData = companyOf(doc.data());
    const fromPath = str(doc.ref.parent.parent?.id);
    const value = fromData || fromPath;
    if (value) hits.push({source: "delegate", companyUID: value});
  }
  return hits;
}

export const ensureStorageUploadIntent = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      fail("unauthenticated", "sign_in_required");
    }
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const folderId = normalizeFolderId(p.folderId ?? p.id);
    if (!isValidFolderId(folderId)) fail("invalid-argument", "folder_id_required");

    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(ctx.auth.uid).get();
    if (!userSnap.exists) fail("permission-denied", "caller_not_staff");
    const user = (userSnap.data() || {}) as Record<string, unknown>;

    const hits = await loadHits(db, folderId);
    const resolved = resolveOwningCompany(hits);
    if (!resolved.ok) fail("failed-precondition", resolved.reason);

    const decision = decideEnsureIntent({
      authenticated: true,
      anonymous: false,
      role: user.role,
      callerCompany: user.companyUID || user.companyId,
      requestedCompany: p.companyUID ?? p.companyId,
      ownerCompany: resolved.companyUID,
      lockedByIntent: resolved.lockedByIntent,
    });
    if (!decision.ok) {
      const code = decision.reason === "sign_in_required" ? "unauthenticated"
        : decision.reason === "company_required" || decision.reason === "company_mismatch"
          ? "invalid-argument"
          : "permission-denied";
      fail(code, decision.reason);
    }

    const ref = db.collection("storage_upload_intents").doc(folderId);
    if (decision.action === "reuse") {
      return {ok: true, created: false, companyUID: decision.companyUID, folderId};
    }
    try {
      await ref.create({
        companyUID: decision.companyUID,
        createdBy: ctx.auth.uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "ensureStorageUploadIntent",
      });
    } catch (err: unknown) {
      const code = typeof err === "object" && err && "code" in err ?
        String((err as {code?: unknown}).code) : "";
      if (code !== "already-exists") throw err;
      const existing = await ref.get();
      const co = companyOf(existing.data());
      if (!co || co !== decision.companyUID) fail("permission-denied", "folder_other_company");
      return {ok: true, created: false, companyUID: co, folderId};
    }
    return {ok: true, created: true, companyUID: decision.companyUID, folderId};
  });
