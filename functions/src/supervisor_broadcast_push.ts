/**
 * TAS-211: attendance / fake-GPS / geofence alerts are written once as
 * notifications with delegateUid = "supervisor_<companyUID>" (TAS-71). The
 * app inbox reads that broadcast, but onNotificationCreated looked up
 * fcm_tokens/supervisor_<co>, found nothing, and no push was sent.
 *
 * This resolves the company's supervisors and company admins on the server
 * and returns their uids, so the caller can push to their own tokens.
 * Push only: no extra notification docs are written.
 */
import type * as admin from "firebase-admin";

export const SUPERVISOR_BROADCAST_PREFIX = "supervisor_";

const SUPERVISOR_POSITIONS = ["supervisor", "Supervisor", "مشرف"];

/** Company id of a supervisor broadcast target, or "" when it is not one. */
export function supervisorBroadcastCompany(delegateUid: unknown): string {
  if (typeof delegateUid !== "string") return "";
  if (!delegateUid.startsWith(SUPERVISOR_BROADCAST_PREFIX)) return "";
  return delegateUid.slice(SUPERVISOR_BROADCAST_PREFIX.length).trim();
}

/** Same audience as the app inbox (isSupervisorOrAdmin), company roles only. */
export function isCompanySupervisorRole(role: unknown): boolean {
  const r = String(role ?? "").trim().toLowerCase();
  if (!r) return false;
  if (r.includes("super") && !r.includes("supervisor")) return false; // super admin: global, not per company
  if (r.includes("support")) return false;
  return r.includes("supervisor") || r.includes("admin");
}

export interface SupervisorSources {
  staffUsers: Array<{uid: string; role?: unknown; status?: unknown}>;
  supervisorDelegates: Array<{uid: string; status?: unknown}>;
}

const INACTIVE = new Set(["suspended", "rejected", "deleted", "inactive", "disabled"]);
const active = (status: unknown) => !INACTIVE.has(String(status ?? "").trim().toLowerCase());

/** Unique recipient uids: company supervisor/admin staff + supervisor delegates. */
export function supervisorRecipientUids(src: SupervisorSources): string[] {
  const out = new Set<string>();
  for (const u of src.staffUsers) {
    if (u.uid && isCompanySupervisorRole(u.role) && active(u.status)) out.add(u.uid);
  }
  for (const d of src.supervisorDelegates) {
    if (d.uid && active(d.status)) out.add(d.uid);
  }
  return Array.from(out);
}

/** Loads the sources for [companyId] (and the org path when known). */
export async function loadSupervisorSources(
  db: admin.firestore.Firestore,
  companyId: string,
  organizationId: string,
): Promise<SupervisorSources> {
  const users = db.collection("users");
  const [byUid, byId] = await Promise.all([
    users.where("companyUID", "==", companyId).get(),
    users.where("companyId", "==", companyId).get(),
  ]);
  const staffUsers = new Map<string, {uid: string; role?: unknown; status?: unknown}>();
  for (const snap of [byUid, byId]) {
    for (const doc of snap.docs) staffUsers.set(doc.id, {uid: doc.id, role: doc.get("role"), status: doc.get("status")});
  }
  const supervisorDelegates: Array<{uid: string; status?: unknown}> = [];
  if (organizationId) {
    const snap = await db
      .collection(`organizations/${organizationId}/companies/${companyId}/delegates`)
      .where("position", "in", SUPERVISOR_POSITIONS)
      .get();
    for (const doc of snap.docs) {
      supervisorDelegates.push({uid: String(doc.get("uid") || doc.id), status: doc.get("status")});
    }
  }
  return {staffUsers: Array.from(staffUsers.values()), supervisorDelegates};
}
