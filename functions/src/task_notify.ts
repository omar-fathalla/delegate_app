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
  assignmentNeedsCompanyDelegates,
  assignmentNeedsSectorStaff,
  newlyAssignedTaskUserIdsFromSources,
  parseAssignedTo,
  taskNotifyUserIdsFromSources,
  taskUsersFromDelegateDocs,
  TaskUser,
} from "./task_notify_logic";
import {upsertTaskImageGrant} from "./task_image_access";

if (admin.apps.length === 0) admin.initializeApp();

const NOTIFY_TITLE = "مهمة جديدة";
const BATCH_LIMIT = 400;

function notifyBody(title: unknown): string {
  const t = String(title || "").trim();
  return t ? `تم تعيين مهمة جديدة لك: ${t}` : "تم تعيين مهمة جديدة لك";
}

/**
 * Same source the task picker reads for «الكل»: organizations/{org}/companies/{co}/delegates.
 * Paginates in pages of 1000.
 */
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

/**
 * Sector-token source used in 401af71: the `users` collection, filtered
 * later by company and role. Includes org-level marketing (no company)
 * via equality queries that do not need a composite index.
 */
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

async function loadSources(
  db: FirebaseFirestore.Firestore,
  assignedTo: unknown,
  opts: {companyId: string; organizationId: string},
): Promise<{delegates: TaskUser[]; sectorStaff: TaskUser[]}> {
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
  return {delegates, sectorStaff};
}

async function resolveRecipients(
  db: FirebaseFirestore.Firestore,
  assignedTo: unknown,
  opts: {companyId: string; organizationId: string; createdBy: string},
): Promise<{ids: string[]; users: TaskUser[]}> {
  const parsed = parseAssignedTo(assignedTo);
  if (parsed.kind === "empty") return {ids: [], users: []};
  const {delegates, sectorStaff} = await loadSources(db, assignedTo, opts);
  const users = [...delegates, ...sectorStaff];
  return {
    ids: taskNotifyUserIdsFromSources(delegates, sectorStaff, assignedTo, opts),
    users,
  };
}

async function senderFields(
  db: FirebaseFirestore.Firestore,
  task: FirebaseFirestore.DocumentData,
  users: TaskUser[],
): Promise<{senderName: string; senderRole: string}> {
  let senderName = String(task.createdByName || task.senderName || "").trim();
  const createdBy = String(task.createdBy || "").trim();
  const fromTask = String(task.createdByRole || task.senderRole || "").trim();
  const fromUser = users.find((u) => u.id === createdBy);
  let senderRole = fromTask || String(fromUser?.role || "").trim();
  // Staff senders (org admin, etc.) may not be in the company delegates
  // list. Look up their profile only to label the card, never for recipients.
  if (createdBy && (!senderName || !senderRole)) {
    const snap = await db.collection("users").doc(createdBy).get();
    if (snap.exists) {
      const data = snap.data() || {};
      if (!senderName) {
        senderName = String(data.displayName || data.fullName || data.name || "").trim();
      }
      if (!senderRole) senderRole = String(data.role || "").trim();
    }
  }
  if (!senderRole && senderName) senderRole = "supervisor";
  return {senderName, senderRole};
}

async function writeTaskNotifications(args: {
  recipientIds: string[];
  organizationId: string;
  companyId: string;
  taskId: string;
  title: unknown;
  senderName?: string;
  senderRole?: string;
}): Promise<number> {
  const {recipientIds, organizationId, companyId, taskId, title, senderName, senderRole} = args;
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
        ...(senderName ? {senderName, createdByName: senderName} : {}),
        ...(senderRole ? {senderRole} : {}),
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
      const {ids: recipientIds, users} = await resolveRecipients(admin.firestore(), task.assignedTo, {
        companyId,
        organizationId,
        createdBy,
      });
      try {
        await upsertTaskImageGrant(admin.firestore(), {
          imagePath: task.imagePath,
          createdBy,
          recipientIds,
          companyUID: companyId,
          organizationId,
          taskId,
        });
      } catch (grantErr) {
        console.error("Error writing task image grant on create:", grantErr);
      }
      if (recipientIds.length === 0) {
        console.log("No recipients for new task:", taskId, "assignedTo=", task.assignedTo);
        return null;
      }
      const sender = await senderFields(admin.firestore(), task, users);
      const n = await writeTaskNotifications({
        recipientIds,
        organizationId,
        companyId,
        taskId,
        title: task.title,
        senderName: sender.senderName,
        senderRole: sender.senderRole,
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
        if (String(before.imagePath || "") !== String(after.imagePath || "")) {
          try {
            const {ids} = await resolveRecipients(admin.firestore(), after.assignedTo, {
              companyId,
              organizationId,
              createdBy,
            });
            await upsertTaskImageGrant(admin.firestore(), {
              imagePath: after.imagePath,
              previousImagePath: before.imagePath,
              createdBy,
              recipientIds: ids,
              companyUID: companyId,
              organizationId,
              taskId,
            });
          } catch (grantErr) {
            console.error("Error writing task image grant on image change:", grantErr);
          }
        }
        return null;
      }
      const db = admin.firestore();
      const beforeAssigned = before.assignedTo;
      const afterAssigned = after.assignedTo;
      const needDelegates = assignmentNeedsCompanyDelegates(beforeAssigned) ||
        assignmentNeedsCompanyDelegates(afterAssigned);
      const needSector = assignmentNeedsSectorStaff(beforeAssigned) ||
        assignmentNeedsSectorStaff(afterAssigned);
      const [delegates, sectorStaff] = await Promise.all([
        needDelegates ?
          loadCompanyDelegates(db, organizationId, companyId) :
          Promise.resolve([] as TaskUser[]),
        needSector ?
          loadSectorStaffFromUsers(db, companyId, organizationId) :
          Promise.resolve([] as TaskUser[]),
      ]);
      const users = [...delegates, ...sectorStaff];
      const newly = newlyAssignedTaskUserIdsFromSources(
        delegates, sectorStaff, beforeAssigned, afterAssigned, {
          companyId,
          organizationId,
          createdBy,
        });
      if (newly.length === 0) {
        console.log("No new recipients for updated task:", taskId);
        return null;
      }
      const sender = await senderFields(db, after, users);
      const n = await writeTaskNotifications({
        recipientIds: newly,
        organizationId,
        companyId,
        taskId,
        title: after.title,
        senderName: sender.senderName,
        senderRole: sender.senderRole,
      });
      console.log(`Created ${n} new-assignment notifications for ${taskId}`);
      try {
        const {ids} = await resolveRecipients(db, after.assignedTo, {
          companyId,
          organizationId,
          createdBy,
        });
        await upsertTaskImageGrant(db, {
          imagePath: after.imagePath,
          previousImagePath: before.imagePath,
          createdBy,
          recipientIds: ids,
          companyUID: companyId,
          organizationId,
          taskId,
        });
      } catch (grantErr) {
        console.error("Error writing task image grant on assignment change:", grantErr);
      }
      return null;
    } catch (error) {
      console.error("Error in onTaskUpdated:", error);
      return null;
    }
  });
