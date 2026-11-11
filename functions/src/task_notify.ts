/**
 * New-task notifications. Recipients are resolved from the app's
 * `assignedTo` string (a uid, `all` / «الكل», or a sector token),
 * company-scoped and de-duplicated. Firestore notification docs are
 * written here; FCM is left to onNotificationCreated so each person
 * gets one push.
 *
 * Deploy (tashil-dev only, named):
 *   functions:tashil-mobile-notifications:onTaskCreated
 *   functions:tashil-mobile-notifications:onTaskUpdated
 * Never deploy suspendExpiredSubscriptions with these.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  parseAssignedTo,
  newlyAssignedTaskUserIds,
  taskNotifyUserIds,
  TaskUser,
} from "./task_notify_logic";

if (admin.apps.length === 0) admin.initializeApp();

const NOTIFY_TITLE = "مهمة جديدة";
const BATCH_LIMIT = 400;

function notifyBody(title: unknown): string {
  const t = String(title || "").trim();
  return t ? `تم تعيين مهمة جديدة لك: ${t}` : "تم تعيين مهمة جديدة لك";
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
  };
}

async function loadGroupCandidates(
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
    // Equality pairs only — avoid a composite index on organizationUIDs+role.
    const marketingRoles = [
      "marketing",
      "marketingPromotion",
      "marketing_promotion",
      "marketing-promotion",
      "branches_marketing",
      "branches-marketing",
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
      if (!seen.has(doc.id)) seen.set(doc.id, asUser(doc.id, doc.data()));
    }
  }
  return Array.from(seen.values());
}

async function loadUsersByIds(
  db: FirebaseFirestore.Firestore,
  uids: string[],
): Promise<TaskUser[]> {
  const out: TaskUser[] = [];
  for (const id of uids) {
    const snap = await db.collection("users").doc(id).get();
    if (snap.exists) out.push(asUser(snap.id, snap.data() as FirebaseFirestore.DocumentData));
  }
  return out;
}

async function resolveRecipients(
  db: FirebaseFirestore.Firestore,
  assignedTo: unknown,
  opts: {companyId: string; organizationId: string; createdBy: string},
): Promise<string[]> {
  const parsed = parseAssignedTo(assignedTo);
  if (parsed.kind === "empty") return [];
  let users: TaskUser[] = [];
  if (parsed.kind === "uids") {
    users = await loadUsersByIds(db, parsed.uids);
  } else {
    users = await loadGroupCandidates(db, opts.companyId, opts.organizationId);
    if (parsed.kind === "mixed") {
      const extra = await loadUsersByIds(db, parsed.uids);
      const seen = new Set(users.map((u) => u.id));
      for (const u of extra) {
        if (!seen.has(u.id)) users.push(u);
      }
    }
  }
  return taskNotifyUserIds(users, assignedTo, opts);
}

async function writeTaskNotifications(args: {
  recipientIds: string[];
  organizationId: string;
  companyId: string;
  taskId: string;
  title: unknown;
}): Promise<number> {
  const {recipientIds, organizationId, companyId, taskId, title} = args;
  if (recipientIds.length === 0) return 0;
  const db = admin.firestore();
  const body = notifyBody(title);
  let written = 0;
  for (let i = 0; i < recipientIds.length; i += BATCH_LIMIT) {
    const chunk = recipientIds.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const delegateUid of chunk) {
      const ref = db.collection("notifications").doc();
      batch.set(ref, {
        delegateUid,
        organizationId,
        companyId: companyId || "",
        title: NOTIFY_TITLE,
        body,
        type: "task",
        taskId,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    written += chunk.length;
  }
  return written;
}

export const onTaskCreated = functions.firestore
  .document("organizations/{organizationId}/tasks/{taskId}")
  .onCreate(async (snap, context) => {
    const task = snap.data();
    const taskId = context.params.taskId;
    const organizationId = context.params.organizationId;
    const companyId = String(task.companyId || task.companyUID || "").trim();
    const createdBy = String(task.createdBy || "").trim();

    try {
      const recipientIds = await resolveRecipients(admin.firestore(), task.assignedTo, {
        companyId,
        organizationId,
        createdBy,
      });
      if (recipientIds.length === 0) {
        console.log("No recipients for new task:", taskId, "assignedTo=", task.assignedTo);
        return null;
      }
      const n = await writeTaskNotifications({
        recipientIds,
        organizationId,
        companyId,
        taskId,
        title: task.title,
      });
      console.log(`Created ${n} new-task notifications for ${taskId}`);
      return null;
    } catch (error) {
      console.error("Error in onTaskCreated:", error);
      return null;
    }
  });

export const onTaskUpdated = functions.firestore
  .document("organizations/{organizationId}/tasks/{taskId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const taskId = context.params.taskId;
    const organizationId = context.params.organizationId;
    const companyId = String(after.companyId || after.companyUID || "").trim();
    const createdBy = String(after.createdBy || "").trim();

    try {
      if (before.assignedTo === after.assignedTo) {
        return null;
      }
      const db = admin.firestore();
      const parsedAfter = parseAssignedTo(after.assignedTo);
      const parsedBefore = parseAssignedTo(before.assignedTo);
      const needsGroup = parsedAfter.kind === "group" || parsedAfter.kind === "mixed" ||
        parsedBefore.kind === "group" || parsedBefore.kind === "mixed";
      const users = needsGroup ?
        await loadGroupCandidates(db, companyId, organizationId) :
        await loadUsersByIds(db, [
          ...(parsedBefore.kind === "uids" ? parsedBefore.uids : []),
          ...(parsedAfter.kind === "uids" ? parsedAfter.uids : []),
        ]);
      const newly = newlyAssignedTaskUserIds(users, before.assignedTo, after.assignedTo, {
        companyId,
        organizationId,
        createdBy,
      });
      if (newly.length === 0) {
        console.log("No new recipients for updated task:", taskId);
        return null;
      }
      const n = await writeTaskNotifications({
        recipientIds: newly,
        organizationId,
        companyId,
        taskId,
        title: after.title,
      });
      console.log(`Created ${n} new-assignment notifications for ${taskId}`);
      return null;
    } catch (error) {
      console.error("Error in onTaskUpdated:", error);
      return null;
    }
  });
