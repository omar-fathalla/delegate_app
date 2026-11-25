/**
 * getTaskProofImage: authorized bytes for a delegate proof photo.
 * Clients never use a public download URL.
 *
 * Visibility: the uploading delegate (including held readers of their
 * own existing photos), the task sender, and same-company company
 * supervisors/admins. Other assignees, HR, accountants, marketing
 * who are not the sender, other companies, tech support, and super
 * admin are denied.
 *
 * Deploy: functions:getTaskProofImage,functions:onTaskDeleted,functions:onTaskProofWritten --project tashil-dev
 * Never deploy suspendExpiredSubscriptions with this function.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {callerDelegateId} from "./caller_delegate_id";
import {
  canReadTaskProof,
  normalizeTaskProofPath,
  parseTaskProofPath,
  proofDisplayNameFrom,
  str,
  taskProofPathsFrom,
} from "./task_proof_access_logic";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 30, memory: "256MB" as const};
const MAX_BYTES = 5 * 1024 * 1024;

function fail(code: functions.https.FunctionsErrorCode, reason: string): never {
  throw new functions.https.HttpsError(code, reason, {reason});
}

async function stripDownloadTokens(file: any): Promise<void> {
  try {
    const [meta] = await file.getMetadata();
    const custom = {...(meta.metadata || {})};
    if (!Object.prototype.hasOwnProperty.call(custom, "firebaseStorageDownloadTokens")) {
      return;
    }
    delete custom.firebaseStorageDownloadTokens;
    await file.setMetadata({metadata: custom});
  } catch (err) {
    functions.logger.warn("strip proof download tokens failed", err);
  }
}

async function readProofBytes(imagePath: string): Promise<{contentType: string; data: string}> {
  const bucket = admin.storage().bucket();
  const file = bucket.file(imagePath);
  const [exists] = await file.exists();
  if (!exists) fail("not-found", "image_not_found");
  const [buf] = await file.download();
  if (buf.length > MAX_BYTES) fail("failed-precondition", "too_large");
  await stripDownloadTokens(file);
  const [meta] = await file.getMetadata();
  const contentType = String(meta.contentType || "image/jpeg");
  return {contentType, data: buf.toString("base64")};
}

async function loadCaller(
  db: FirebaseFirestore.Firestore,
  uid: string,
  orgId: string,
  companyId: string,
  delegateId: string = uid,
): Promise<{role: unknown; companyUID: string}> {
  const userSnap = await db.collection("users").doc(uid).get();
  if (userSnap.exists) {
    const d = (userSnap.data() || {}) as Record<string, unknown>;
    return {
      role: d.role,
      companyUID: str(d.companyUID) || str(d.companyId),
    };
  }
  if (orgId && companyId) {
    const del = await db.doc(
      `organizations/${orgId}/companies/${companyId}/delegates/${delegateId}`,
    ).get();
    if (del.exists) {
      const d = (del.data() || {}) as Record<string, unknown>;
      return {
        role: d.role || "delegate",
        companyUID: str(d.companyUID) || str(d.companyId) || companyId,
      };
    }
  }
  return {role: "", companyUID: ""};
}

export const getTaskProofImage = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth) fail("unauthenticated", "sign_in_required");
    if (ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      fail("unauthenticated", "sign_in_required");
    }
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const imagePath = normalizeTaskProofPath(p.imagePath ?? p.path);
    const parsed = parseTaskProofPath(imagePath);
    if (!parsed) fail("invalid-argument", "invalid_path");
    const taskId = str(p.taskId);
    const organizationId = str(p.organizationId) || str(p.organizationUID);
    if (!taskId || !organizationId) fail("invalid-argument", "task_required");

    const db = admin.firestore();
    const taskSnap = await db.doc(`organizations/${organizationId}/tasks/${taskId}`).get();
    if (!taskSnap.exists) fail("not-found", "task_not_found");
    const task = (taskSnap.data() || {}) as Record<string, unknown>;
    const taskCompany = str(task.companyId) || str(task.companyUID);
    const createdBy = str(task.createdBy);

    const proofSnap = await taskSnap.ref.collection("proofs").doc(parsed.uploaderUid).get();
    if (!proofSnap.exists) fail("permission-denied", "not_allowed");
    const proof = (proofSnap.data() || {}) as Record<string, unknown>;
    const proofPaths = taskProofPathsFrom(proof.imagePaths);
    const proofCompany = str(proof.companyUID) || str(proof.companyId);

    const caller = await loadCaller(db, ctx.auth.uid, organizationId, taskCompany,
      callerDelegateId(ctx.auth.uid, ctx.auth.token as unknown as Record<string, unknown>));
    const decision = canReadTaskProof({
      authenticated: true,
      anonymous: false,
      // TAS-28 phase 0: delegateId claim (same as the uid today).
      callerUid: callerDelegateId(ctx.auth.uid, ctx.auth.token as unknown as Record<string, unknown>),
      callerRole: caller.role,
      callerCompany: caller.companyUID,
      uploaderUid: parsed.uploaderUid,
      taskCreatedBy: createdBy,
      taskCompanyId: taskCompany,
      requestedPath: imagePath,
      proofPaths,
      proofCompanyId: proofCompany || parsed.companyId,
    });
    if (!decision.ok) {
      const code = decision.reason === "sign_in_required" ? "unauthenticated"
        : decision.reason === "invalid_path" || decision.reason === "path_mismatch"
          || decision.reason === "company_mismatch"
          ? "invalid-argument"
          : "permission-denied";
      fail(code, decision.reason);
    }
    return await readProofBytes(imagePath);
  });

/** Admin cleanup of per-uploader proof files when a task is hard-deleted. */
export const onTaskDeleted = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .firestore.document("organizations/{orgId}/tasks/{taskId}")
  .onDelete(async (snap) => {
    const proofs = await snap.ref.collection("proofs").get();
    if (proofs.empty) return;
    const bucket = admin.storage().bucket();
    for (const doc of proofs.docs) {
      const paths = taskProofPathsFrom((doc.data() || {}).imagePaths);
      for (const path of paths) {
        try {
          await bucket.file(path).delete();
        } catch (err) {
          functions.logger.warn("proof file delete failed", {path, err});
        }
      }
      try {
        await doc.ref.delete();
      } catch (err) {
        functions.logger.warn("proof doc delete failed", {id: doc.id, err});
      }
    }
  });

/**
 * B1: the uploader label on a proofs doc comes from the uploader's own
 * profile, never from the client. Rules forbid clients from adding or
 * changing uploadedByName; this trigger sets it (idempotent: no write
 * when it already matches, so it does not loop).
 */
export const onTaskProofWritten = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .firestore.document("organizations/{orgId}/tasks/{taskId}/proofs/{uploaderUid}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return;
    const data = (change.after.data() || {}) as Record<string, unknown>;
    const uid = str(context.params.uploaderUid);
    const orgId = str(context.params.orgId);
    const companyId = str(data.companyUID);
    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(uid).get();
    let delegate: Record<string, unknown> | null = null;
    if (orgId && companyId && !companyId.includes("/")) {
      const del = await db.doc(
        `organizations/${orgId}/companies/${companyId}/delegates/${uid}`,
      ).get();
      if (del.exists) delegate = (del.data() || {}) as Record<string, unknown>;
    }
    const name = proofDisplayNameFrom(
      userSnap.exists ? (userSnap.data() || {}) as Record<string, unknown> : null,
      delegate,
    );
    const current = typeof data.uploadedByName === "string" ? data.uploadedByName : null;
    if (name) {
      if (current === name) return;
      await change.after.ref.update({uploadedByName: name});
    } else if (current !== null) {
      await change.after.ref.update({uploadedByName: admin.firestore.FieldValue.delete()});
    }
  });
