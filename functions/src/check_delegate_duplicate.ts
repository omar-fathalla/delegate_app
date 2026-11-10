import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  decideDuplicate,
  DuplicateHit,
  isExistingDelegateStatus,
  isOpenRequestStatus,
  normalizeIdDigits,
  publicDuplicateResult,
} from "./check_delegate_duplicate_logic";

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

function isCompanyStaff(role: string): boolean {
  const r = canonicalizeRole(role);
  return [
    "company-admin", "companyadmin", "admin", "supervisor", "company-supervisor",
    "hr", "company-hr", "human-resources",
  ].includes(r);
}

function companyOf(data: FirebaseFirestore.DocumentData | undefined): {uid: string; name: string} {
  const uid = String(data?.companyUID || data?.companyId || "").trim();
  const name = String(data?.companyName || data?.company_name || "").trim();
  return {uid, name};
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
    if (!nationalId && !phoneNumber) {
      throw new functions.https.HttpsError("invalid-argument", "nationalId or phoneNumber is required.");
    }
    if (!companyUID) {
      throw new functions.https.HttpsError("invalid-argument", "companyUID is required.");
    }
    const callerCompany = String(caller.companyUID || caller.companyId || "").trim();
    if (isCompanyStaff(role) && callerCompany && callerCompany !== companyUID) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed.");
    }

    const hits: DuplicateHit[] = [];
    const seen = new Set<string>();
    const addHit = (hit: DuplicateHit) => {
      if (!hit.companyUID) return;
      const key = `${hit.companyUID}|${hit.field}`;
      if (seen.has(key)) return;
      seen.add(key);
      hits.push(hit);
    };

    const scanRequests = async (field: "nationalId" | "nationalityID" | "phoneNumber", value: string, kind: DuplicateHit["field"]) => {
      const snap = await db.collection("delegate_requests").where(field, "==", value).get();
      for (const doc of snap.docs) {
        if (!isOpenRequestStatus(doc.data().status)) continue;
        const co = companyOf(doc.data());
        addHit({companyUID: co.uid, companyName: co.name, field: kind});
      }
    };

    const scanDelegates = async (field: "nationalId" | "nationalityID" | "phoneNumber", value: string, kind: DuplicateHit["field"]) => {
      const snap = await db.collectionGroup("delegates").where(field, "==", value).get();
      for (const doc of snap.docs) {
        if (!isExistingDelegateStatus(doc.data().status)) continue;
        const co = companyOf(doc.data());
        addHit({companyUID: co.uid, companyName: co.name, field: kind});
      }
    };

    if (nationalId) {
      await scanRequests("nationalId", nationalId, "nationalId");
      await scanRequests("nationalityID", nationalId, "nationalId");
      await scanDelegates("nationalId", nationalId, "nationalId");
      await scanDelegates("nationalityID", nationalId, "nationalId");
    }
    if (phoneNumber) {
      await scanRequests("phoneNumber", phoneNumber, "phoneNumber");
      await scanDelegates("phoneNumber", phoneNumber, "phoneNumber");
    }

    return publicDuplicateResult(decideDuplicate(companyUID, hits));
  });
