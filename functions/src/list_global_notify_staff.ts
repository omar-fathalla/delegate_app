import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {PRIVILEGED_ALERT_ROLE_VALUES} from "./delegate_profile_edit_logic";

/** Firestore `whereIn` role spellings for global notify targets (TA-35). */
export const GLOBAL_NOTIFY_TARGET_ROLES = [
  ...PRIVILEGED_ALERT_ROLE_VALUES,
  "tech_support",
  "techsupport",
] as const;

export const GLOBAL_NOTIFY_STAFF_CAP = 50;

const COMPANY_NOTIFY_ROLES = new Set([
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
  "hr", "company-hr", "company_hr", "human_resources",
]);

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export type GlobalNotifyStaffRow = {
  uid: string;
  phoneNumber: string;
  role: string;
};

export function companyNotifyCallerAllowed(
  caller: {role?: unknown; companyUID?: unknown; companyId?: unknown},
): boolean {
  const role = str(caller.role);
  const companyUID = str(caller.companyUID) || str(caller.companyId);
  return companyUID !== "" && COMPANY_NOTIFY_ROLES.has(role);
}

function notifyTargetEligible(data: admin.firestore.DocumentData): boolean {
  const status = str(data.status).toLowerCase();
  if (status === "suspended" || status === "deleted" || status === "inactive") {
    return false;
  }
  if (data.isActive === false) return false;
  if (data.deleted === true) return false;
  return true;
}

/**
 * Supervisor new-delegate flow: list global staff for targeted notifications (TA-35).
 * Returns uid + phone + role only — never full user documents.
 */
export async function listGlobalNotifyStaffRows(
  db: admin.firestore.Firestore,
): Promise<GlobalNotifyStaffRow[]> {
  const snap = await db.collection("users").where("role", "in", [
    ...GLOBAL_NOTIFY_TARGET_ROLES,
  ]).get();
  const rows: GlobalNotifyStaffRow[] = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (!notifyTargetEligible(data)) continue;
    rows.push({
      uid: doc.id,
      phoneNumber: str(data.phoneNumber) || str(data.phone),
      role: str(data.role),
    });
    if (rows.length >= GLOBAL_NOTIFY_STAFF_CAP) break;
  }
  return rows;
}

export const listGlobalNotifyStaff = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (_data: unknown, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const db = admin.firestore();
    const caller = (await db.collection("users").doc(context.auth.uid).get()).data() || {};
    if (!companyNotifyCallerAllowed(caller)) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed.");
    }
    return {users: await listGlobalNotifyStaffRows(db)};
  });