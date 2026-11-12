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
  isInactiveStatus,
  isTaskImageFolderId,
  isTaskImagePurpose,
  isTaskProofFolderId,
  isTaskProofPurpose,
  isValidFolderId,
  normalizeFolderId,
  resolveOwningCompany,
  type OwnerHit,
} from "./storage_upload_intent_logic";
import {hasAnyHold, parseHolds} from "./holds";

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
    const purpose = typeof p.purpose === "string" ? p.purpose.trim() : "";
    if (isTaskImagePurpose(purpose) && !isTaskImageFolderId(folderId, ctx.auth.uid)) {
      fail("invalid-argument", "folder_id_required");
    }
    if (isTaskProofPurpose(purpose) && !isTaskProofFolderId(folderId, ctx.auth.uid)) {
      fail("invalid-argument", "folder_id_required");
    }

    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(ctx.auth.uid).get();
    let user = (userSnap.data() || {}) as Record<string, unknown>;
    if (!userSnap.exists) {
      if (!isTaskProofPurpose(purpose)) fail("permission-denied", "caller_not_staff");
      const orgHint = str(p.organizationId) || str(p.organizationUID);
      const coHint = str(p.companyUID) || str(p.companyId);
      let delSnap: FirebaseFirestore.DocumentSnapshot | null = null;
      if (orgHint && coHint) {
        delSnap = await db.doc(
          `organizations/${orgHint}/companies/${coHint}/delegates/${ctx.auth.uid}`,
        ).get();
      }
      if (!delSnap || !delSnap.exists) {
        fail("permission-denied", "caller_not_staff");
      }
      const d = (delSnap.data() || {}) as Record<string, unknown>;
      user = {
        role: d.role || "delegate",
        companyUID: d.companyUID || d.companyId || coHint,
        organizationUID: d.organizationUID || d.organizationId || orgHint,
        status: d.status,
        holds: d.holds,
        isActive: d.isActive,
      };
    }
    const authUser = await admin.auth().getUser(ctx.auth.uid);
    if (authUser.disabled || user.isActive === false || isInactiveStatus(user.status)) {
      fail("permission-denied", "caller_inactive");
    }
    if (isTaskProofPurpose(purpose) && hasAnyHold(parseHolds(user.holds))) {
      fail("permission-denied", "caller_held");
    }
    const orgId = str(user.organizationUID) || str(user.organizationId);
    if (orgId) {
      const org = await db.collection("organizations").doc(orgId).get();
      const od = (org.data() || {}) as Record<string, unknown>;
      if (org.exists && (od.isActive === false || isInactiveStatus(od.status))) {
        fail("permission-denied", "org_inactive");
      }
    }

    // Task-image intents are a reserved object name for the caller's
    // company. Do not resolve them against request or delegate folders.
    let resolved: {companyUID: string | null; lockedByIntent: boolean};
    if (isTaskImagePurpose(purpose) || isTaskProofPurpose(purpose)) {
      const existing = await db.collection("storage_upload_intents").doc(folderId).get();
      const co = companyOf(existing.data());
      resolved = existing.exists && co
        ? {companyUID: co, lockedByIntent: true}
        : {companyUID: null, lockedByIntent: false};
    } else {
      const hits = await loadHits(db, folderId);
      const resolvedHits = resolveOwningCompany(hits);
      if (!resolvedHits.ok) fail("failed-precondition", resolvedHits.reason);
      resolved = resolvedHits;
    }

    const decision = decideEnsureIntent({
      authenticated: true,
      anonymous: false,
      role: user.role,
      callerCompany: user.companyUID || user.companyId,
      requestedCompany: p.companyUID ?? p.companyId,
      ownerCompany: resolved.companyUID,
      lockedByIntent: resolved.lockedByIntent,
      purpose,
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
        ...(isTaskImagePurpose(purpose) ? {purpose: "task_image"} : {}),
        ...(isTaskProofPurpose(purpose) ? {purpose: "task_proof_image"} : {}),
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
