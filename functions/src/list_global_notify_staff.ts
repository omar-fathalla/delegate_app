import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {PRIVILEGED_ALERT_ROLE_VALUES} from "./delegate_profile_edit_logic";

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

/**
 * Supervisor new-delegate flow: list global staff for targeted notifications (TA-35).
 * Returns uid + phone + role only — never full user documents.
 */
export async function listGlobalNotifyStaffRows(
  db: admin.firestore.Firestore,
): Promise<GlobalNotifyStaffRow[]> {
  const snap = await db.collection("users").where("role", "in", [
    ...PRIVILEGED_ALERT_ROLE_VALUES,
  ]).get();
  const rows: GlobalNotifyStaffRow[] = [];
  for (const doc of snap.docs) {
    rows.push({
      uid: doc.id,
      phoneNumber: str(doc.get("phoneNumber")) || str(doc.get("phone")),
      role: str(doc.get("role")),
    });
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
    const role = str(caller.role);
    const companyUID = str(caller.companyUID) || str(caller.companyId);
    if (!companyUID || !COMPANY_NOTIFY_ROLES.has(role)) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed.");
    }
    return {users: await listGlobalNotifyStaffRows(db)};
  });