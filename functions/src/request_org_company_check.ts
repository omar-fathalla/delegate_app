/**
 * Server-side enforcement for secondary organizationUIDs: each chain must
 * have organizations/{org}/companies/{company}. Logs the reason.
 *
 * Deploy: functions:tashil-mobile-notifications:auditDelegateRequestOrgs
 * Do not deploy suspendExpiredSubscriptions with this function.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {
  requestCompanyId,
  requestOrganizationIds,
  summarizeOrgCompanyCheck,
} from "./request_org_company";

if (admin.apps.length === 0) admin.initializeApp();

export async function missingOrgsForCompany(
  db: FirebaseFirestore.Firestore,
  companyUID: string,
  orgIds: string[],
): Promise<string[]> {
  const missing: string[] = [];
  for (const orgId of orgIds) {
    const snap = await db.doc(`organizations/${orgId}/companies/${companyUID}`).get();
    if (!snap.exists) missing.push(orgId);
  }
  return missing;
}

export async function evaluateRequestOrgCompany(
  db: FirebaseFirestore.Firestore,
  data: Record<string, unknown>,
): Promise<ReturnType<typeof summarizeOrgCompanyCheck>> {
  const companyUID = requestCompanyId(data);
  const orgIds = requestOrganizationIds(data);
  const missing = companyUID ? await missingOrgsForCompany(db, companyUID, orgIds) : orgIds;
  return summarizeOrgCompanyCheck({companyUID, orgIds, missing});
}

export const auditDelegateRequestOrgs = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .firestore.document("delegate_requests/{requestId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const before = (change.before.exists ? change.before.data() : {}) as Record<string, unknown>;
    const after = (change.after.data() || {}) as Record<string, unknown>;
    const keys = ["organizationUIDs", "organizationUID", "organizationId", "companyUID", "companyId"];
    const changed = !change.before.exists ||
      keys.some((k) => JSON.stringify(before[k] ?? null) !== JSON.stringify(after[k] ?? null));
    const markMissing = typeof after.orgCompanyCheck !== "string" || after.orgCompanyCheck === "";
    if (!changed && !markMissing) return null;
    const result = await evaluateRequestOrgCompany(admin.firestore(), after);
    if (!result.ok) {
      functions.logger.warn("delegate request org is not in company", {
        requestId: context.params.requestId,
        reason: result.reason,
        companyUID: result.companyUID,
        missing: result.missing,
      });
    } else {
      functions.logger.info("delegate request orgs belong to company", {
        requestId: context.params.requestId,
        reason: result.reason,
        companyUID: result.companyUID,
        orgIds: result.orgIds,
      });
    }
    const next = result.ok ? "ok" : "failed";
    if (after.orgCompanyCheck === next) return null;
    await change.after.ref.update({
      orgCompanyCheck: next,
      orgCompanyCheckReason: result.reason,
      orgCompanyCheckMissing: result.missing,
      orgCompanyCheckAt: FieldValue.serverTimestamp(),
    });
    return null;
  });

/**
 * If a client creates a nested delegate under a company that does not exist
 * in that organization, delete the doc and log. Admin SDK company creates
 * in the same batch are visible here after commit.
 *
 * Deploy: functions:tashil-mobile-notifications:auditDelegateCreateOrgs
 * Do not deploy suspendExpiredSubscriptions with this function.
 */
export const auditDelegateCreateOrgs = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .firestore.document("organizations/{orgId}/companies/{companyId}/delegates/{uid}")
  .onCreate(async (snap, context) => {
    const orgId = String(context.params.orgId || "");
    const companyId = String(context.params.companyId || "");
    const uid = String(context.params.uid || "");
    const parent = await snap.ref.parent.parent?.get();
    if (parent && parent.exists) return null;
    functions.logger.warn("delegate created under a company that is not in the organization", {
      orgId, companyId, uid, path: snap.ref.path, reason: "org_not_in_company",
    });
    await snap.ref.delete();
    return null;
  });
