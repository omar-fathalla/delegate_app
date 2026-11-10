import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  normalizeIdDigits,
  isValidEgyptianNationalId,
} from "./check_delegate_duplicate_logic";
import {findDuplicatePublic} from "./check_delegate_duplicate_query";

const STAFF_ROLES = new Set([
  "super-admin", "super_admin", "superadmin", "superAdmin",
  "technical_support", "technical-support", "technicalSupport", "technicalsupport",
  "organization-admin", "organization_admin", "organizationadmin", "organizationAdmin",
  "company-admin", "company_admin", "companyadmin", "admin",
  "supervisor", "company_supervisor",
  "hr", "company-hr", "company_hr", "human_resources",
]);

function canonicalizeRole(role: unknown): string {
  return String(role || "").trim().toLowerCase().replace(/_/g, "-");
}

function isGlobalStaff(role: string): boolean {
  const r = canonicalizeRole(role);
  return r === "super-admin" || r === "superadmin" ||
    r === "technical-support" || r === "technicalsupport" || r === "tech-support" || r === "techsupport";
}

function isOrgAdmin(role: string): boolean {
  const r = canonicalizeRole(role);
  return r === "organization-admin" || r === "organizationadmin";
}

/**
 * checkDelegateDuplicate (staff-only)
 * Input: { nationalId: string, phoneNumber: string, companyUID: string }
 * Output: { duplicate: boolean, reason?: "same_company" | "another_company", companyName?: string }
 * companyName is returned only for another_company, and is the other company's
 * display name only — no IDs or delegate details.
 *
 * Deploy by name only (not yet deployed):
 *   firebase deploy --only functions:tashil-mobile-notifications:checkDelegateDuplicate --project <project>
 */
const RATE_COLLECTION = "duplicate_check_rate_limits";
const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_MAX = 30;

async function enforceRateLimit(db: FirebaseFirestore.Firestore, uid: string): Promise<void> {
  const ref = db.collection(RATE_COLLECTION).doc(uid);
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const start = typeof data.windowStart === "number" ? data.windowStart : 0;
    const count = typeof data.count === "number" ? data.count : 0;
    if (!start || now - start >= RATE_WINDOW_MS) {
      tx.set(ref, {windowStart: now, count: 1, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      return;
    }
    if (count >= RATE_MAX) {
      throw new functions.https.HttpsError("resource-exhausted", "Too many duplicate checks. Try again later.");
    }
    tx.update(ref, {count: count + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  });
}

export const checkDelegateDuplicate = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth || context.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    const db = admin.firestore();
    const callerSnap = await db.collection("users").doc(context.auth.uid).get();
    const caller = callerSnap.data() || {};
    const role = String(caller.role || "");
    if (!STAFF_ROLES.has(role) && !STAFF_ROLES.has(canonicalizeRole(role))) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed.");
    }
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const nationalId = normalizeIdDigits(typeof payload.nationalId === "string" ? payload.nationalId : "");
    const phoneNumber = normalizeIdDigits(typeof payload.phoneNumber === "string" ? payload.phoneNumber : "");
    const companyUID = typeof payload.companyUID === "string" ? payload.companyUID.trim() : "";
    const excludeDelegateUid = typeof payload.excludeDelegateUid === "string"
      ? payload.excludeDelegateUid.trim() : "";
    if (!nationalId && !phoneNumber) {
      throw new functions.https.HttpsError("invalid-argument", "nationalId or phoneNumber is required.");
    }
    if (nationalId && !isValidEgyptianNationalId(nationalId)) {
      throw new functions.https.HttpsError("invalid-argument", "nationalId-format");
    }
    if (!companyUID) {
      throw new functions.https.HttpsError("invalid-argument", "companyUID is required.");
    }
    const callerCompany = String(caller.companyUID || caller.companyId || "").trim();
    // Company staff may only check inside their company. Super-admin / tech
    // may pass any companyUID. Org-admins on the web only review requests
    // (they do not register delegates). An org-admin without a companyUID
    // is rejected with a specific code so the app can show a clear message
    // instead of the generic «تعذر التحقق».
    if (!isGlobalStaff(role)) {
      if (!callerCompany) {
        if (isOrgAdmin(role)) {
          throw new functions.https.HttpsError("failed-precondition", "org-admin-no-company");
        }
        throw new functions.https.HttpsError("permission-denied", "Not allowed.");
      }
      if (callerCompany !== companyUID) {
        throw new functions.https.HttpsError("permission-denied", "Not allowed.");
      }
    }

    await enforceRateLimit(db, context.auth.uid);

    return findDuplicatePublic(db, {nationalId, phoneNumber, companyUID, excludeDelegateUid});
  });
