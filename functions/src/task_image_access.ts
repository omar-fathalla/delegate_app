/**
 * getTaskImage: authorized bytes for a task image. Clients never use a
 * public download URL. Recipients are the sender plus the same set as
 * new-task notifications.
 *
 * Deploy: functions:tashil-mobile-notifications:getTaskImage
 * Never deploy suspendExpiredSubscriptions with this function.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  assignmentNeedsCompanyDelegates,
  assignmentNeedsSectorStaff,
  parseAssignedTo,
  taskNotifyUserIdsFromSources,
  taskUsersFromDelegateDocs,
  TaskUser,
} from "./task_notify_logic";
import {
  canPreviewUnsentTaskImage,
  canReadTaskImage,
  fileNameFromImagePath,
  grantReaderUids,
  parseTaskImagePath,
  str,
} from "./task_image_access_logic";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 30, memory: "256MB" as const};
const MAX_BYTES = 5 * 1024 * 1024;

function fail(code: functions.https.FunctionsErrorCode, reason: string): never {
  throw new functions.https.HttpsError(code, reason, {reason});
}

function asUser(id: string, data: FirebaseFirestore.DocumentData): TaskUser {
  return {
    id,
    role: data.role,
    companyUID: data.companyUID,
    companyId: data.companyId,
    companyIds: data.companyIds,
    organizationUID: data.organizationUID,
    organizationUIDs: data.organizationUIDs,
    status: data.status,
    holds: data.holds,
  };
}

async function loadCompanyDelegates(
  db: FirebaseFirestore.Firestore,
  organizationId: string,
  companyId: string,
): Promise<TaskUser[]> {
  const co = companyId.trim();
  const org = organizationId.trim();
  if (!co || !org) return [];
  const col = db
    .collection("organizations").doc(org)
    .collection("companies").doc(co)
    .collection("delegates");
  const docs: {id: string; data: Record<string, unknown>}[] = [];
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q: FirebaseFirestore.Query = col.limit(1000);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      docs.push({id: doc.id, data: doc.data() as Record<string, unknown>});
    }
    if (snap.size < 1000) break;
    last = snap.docs[snap.docs.length - 1];
  }
  return taskUsersFromDelegateDocs(docs);
}

async function loadSectorStaffFromUsers(
  db: FirebaseFirestore.Firestore,
  companyId: string,
  organizationId: string,
): Promise<TaskUser[]> {
  const users = db.collection("users");
  const queries: Promise<FirebaseFirestore.QuerySnapshot>[] = [];
  const co = companyId.trim();
  const org = organizationId.trim();
  if (co) {
    queries.push(users.where("companyUID", "==", co).get());
    queries.push(users.where("companyId", "==", co).get());
    queries.push(users.where("companyIds", "array-contains", co).get());
  }
  if (org) {
    const marketingRoles = [
      "marketing",
      "marketingPromotion",
      "marketing_promotion",
      "marketing-promotion",
      "branches_marketing",
      "branches-marketing",
      "branches_marketing_manager",
      "branches-marketing-manager",
      "branchesmarketingmanager",
    ];
    for (const role of marketingRoles) {
      queries.push(users.where("organizationUID", "==", org).where("role", "==", role).get());
    }
  }
  if (queries.length === 0) return [];
  const snaps = await Promise.all(queries);
  const seen = new Map<string, TaskUser>();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (!doc.id || seen.has(doc.id)) continue;
      seen.set(doc.id, asUser(doc.id, doc.data()));
    }
  }
  return Array.from(seen.values());
}

async function resolveRecipientIds(
  db: FirebaseFirestore.Firestore,
  assignedTo: unknown,
  opts: {companyId: string; organizationId: string; createdBy: string},
): Promise<string[]> {
  const parsed = parseAssignedTo(assignedTo);
  if (parsed.kind === "empty") return [];
  const needDelegates = assignmentNeedsCompanyDelegates(assignedTo);
  const needSector = assignmentNeedsSectorStaff(assignedTo);
  const [delegates, sectorStaff] = await Promise.all([
    needDelegates ?
      loadCompanyDelegates(db, opts.organizationId, opts.companyId) :
      Promise.resolve([] as TaskUser[]),
    needSector ?
      loadSectorStaffFromUsers(db, opts.companyId, opts.organizationId) :
      Promise.resolve([] as TaskUser[]),
  ]);
  return taskNotifyUserIdsFromSources(delegates, sectorStaff, assignedTo, opts);
}

export async function upsertTaskImageGrant(
  db: FirebaseFirestore.Firestore,
  opts: {
    imagePath?: unknown;
    previousImagePath?: unknown;
    createdBy: unknown;
    recipientIds: readonly string[];
    companyUID: unknown;
    organizationId: unknown;
    taskId: unknown;
  },
): Promise<void> {
  const current = str(opts.imagePath);
  const previous = str(opts.previousImagePath);
  const currentName = current ? fileNameFromImagePath(current) : "";
  const previousName = previous ? fileNameFromImagePath(previous) : "";
  if (previousName && previousName !== currentName) {
    await db.collection("task_image_grants").doc(previousName).delete().catch(() => undefined);
  }
  if (!current || !currentName || !parseTaskImagePath(current)) {
    if (currentName) {
      await db.collection("task_image_grants").doc(currentName).delete().catch(() => undefined);
    }
    return;
  }
  const readers = grantReaderUids(opts.createdBy, opts.recipientIds);
  await db.collection("task_image_grants").doc(currentName).set({
    imagePath: current,
    companyUID: str(opts.companyUID),
    organizationId: str(opts.organizationId),
    taskId: str(opts.taskId),
    createdBy: str(opts.createdBy),
    readerUids: readers,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// The Admin Storage File typings are not exported as admin.storage.File.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function stripDownloadTokens(file: any): Promise<void> {
  try {
    const [meta] = await file.getMetadata();
    const custom = {...(meta.metadata || {})} as Record<string, string>;
    if (!Object.prototype.hasOwnProperty.call(custom, "firebaseStorageDownloadTokens")) {
      return;
    }
    delete custom.firebaseStorageDownloadTokens;
    await file.setMetadata({metadata: custom});
  } catch (err) {
    console.warn("stripDownloadTokens failed:", err);
  }
}

async function readTaskImageBytes(imagePath: string): Promise<{contentType: string; data: string}> {
  const parsed = parseTaskImagePath(imagePath);
  if (!parsed) fail("invalid-argument", "invalid_path");
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

export const getTaskImage = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      fail("unauthenticated", "sign_in_required");
    }
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const imagePath = str(p.imagePath);
    if (!imagePath) fail("invalid-argument", "image_path_required");
    const taskId = str(p.taskId);
    const organizationId = str(p.organizationId) || str(p.organizationUID);
    const caller = ctx.auth.uid;

    if (!taskId) {
      const preview = canPreviewUnsentTaskImage({callerUid: caller, requestedPath: imagePath});
      if (!preview.ok) fail("permission-denied", preview.reason);
      return await readTaskImageBytes(imagePath);
    }

    if (!organizationId) fail("invalid-argument", "organization_required");
    const db = admin.firestore();
    const snap = await db
      .collection("organizations").doc(organizationId)
      .collection("tasks").doc(taskId)
      .get();
    if (!snap.exists) fail("not-found", "task_not_found");
    const task = snap.data() || {};
    const companyId = str(task.companyId) || str(task.companyUID);
    const createdBy = str(task.createdBy);
    const recipientIds = await resolveRecipientIds(db, task.assignedTo, {
      companyId,
      organizationId,
      createdBy,
    });
    const decision = canReadTaskImage({
      callerUid: caller,
      createdBy,
      recipientIds,
      requestedPath: imagePath,
      taskImagePath: task.imagePath,
      taskCompanyId: companyId,
    });
    if (!decision.ok) fail("permission-denied", decision.reason);
    try {
      await upsertTaskImageGrant(db, {
        imagePath: task.imagePath,
        createdBy,
        recipientIds,
        companyUID: companyId,
        organizationId,
        taskId,
      });
    } catch (err) {
      console.error("upsertTaskImageGrant failed:", err);
    }
    return await readTaskImageBytes(imagePath);
  });

/**
 * Remove public download tokens from new task-image uploads so a copied
 * URL cannot bypass access checks.
 *
 * Deploy: functions:tashil-mobile-notifications:onTaskImageFinalize
 */
export const onTaskImageFinalize = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .storage.object()
  .onFinalize(async (object) => {
    const name = String(object.name || "");
    if (!parseTaskImagePath(name)) return null;
    const bucketName = object.bucket;
    if (!bucketName) return null;
    const file = admin.storage().bucket(bucketName).file(name);
    await stripDownloadTokens(file);
    return null;
  });
