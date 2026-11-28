/**
 * onBranchLocationReportWritten (TAS-397): notifications for «مكان الفرع
 * غلط» reports (branch_location_reports), written by the server. The push
 * goes out from onNotificationCreated. Never writes a branch.
 *
 * Deploy (named only, tashil-dev first, after the rules):
 *   functions:tashil-mobile-notifications:onBranchLocationReportWritten
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  activeStaffUids,
  Audience,
  audiencesFor,
  CHAIN_ADMIN_ROLES,
  COMPANY_SUPERVISOR_ROLES,
  notificationsFor,
  reportEvent,
  SUPER_ADMIN_ROLES,
} from "./branch_location_report_notify_logic";

if (admin.apps.length === 0) admin.initializeApp();

type UserRow = {uid: string; role?: unknown; status?: unknown; isActive?: unknown};

async function usersWhere(
  db: FirebaseFirestore.Firestore,
  field: string,
  value: string,
): Promise<UserRow[]> {
  if (!value) return [];
  const snap = await db.collection("users").where(field, "==", value).get();
  return snap.docs.map((d) => ({uid: d.id, role: d.get("role"), status: d.get("status"),
    isActive: d.get("isActive")}));
}

async function recipients(
  db: FirebaseFirestore.Firestore,
  audience: Audience,
  after: Record<string, unknown>,
): Promise<string[]> {
  const co = String(after.companyUID || "").trim();
  const org = String(after.organizationUID || "").trim();
  if (audience === "delegate") {
    const id = String(after.delegateId || "").trim();
    return id ? [id] : [];
  }
  if (audience === "company_supervisors") {
    const [byUid, byId] = await Promise.all([usersWhere(db, "companyUID", co), usersWhere(db, "companyId", co)]);
    return activeStaffUids([...byUid, ...byId], COMPANY_SUPERVISOR_ROLES);
  }
  // Chain admins of the branch's chain; the super admins when it has none
  // (most chains have no org admin today).
  const chain = activeStaffUids(await usersWhere(db, "organizationUID", org), CHAIN_ADMIN_ROLES);
  if (chain.length > 0) return chain;
  const snap = await db.collection("users").where("role", "in", SUPER_ADMIN_ROLES).get();
  return activeStaffUids(
    snap.docs.map((d) => ({uid: d.id, role: d.get("role"), status: d.get("status"), isActive: d.get("isActive")})),
    SUPER_ADMIN_ROLES,
  );
}

/** Writes the event's notifications once. Exported for the emulator test. */
export async function notifyReport(
  db: FirebaseFirestore.Firestore,
  reportId: string,
  eventId: string,
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): Promise<number> {
  const event = reportEvent(before, after);
  if (!event || !after) return 0;
  let written = 0;
  for (const audience of audiencesFor(event)) {
    const uids = await recipients(db, audience, after);
    for (const n of notificationsFor(event, audience, reportId, eventId, after, uids)) {
      try {
        await db.collection("notifications").doc(n.id).create({
          ...n.doc,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        written++;
      } catch (e) {
        // ALREADY_EXISTS on a retried event: already sent.
        if ((e as {code?: number}).code !== 6) throw e;
      }
    }
  }
  return written;
}

export const onBranchLocationReportWritten = functions.firestore
  .document("branch_location_reports/{reportId}")
  .onWrite(async (change, context) => {
    await notifyReport(
      admin.firestore(),
      context.params.reportId as string,
      context.eventId,
      change.before.exists ? change.before.data() : undefined,
      change.after.exists ? change.after.data() : undefined,
    );
  });
