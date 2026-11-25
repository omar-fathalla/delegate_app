/**
 * syncStaffClaimsOnUserWrite (TAS-23): keeps the staff role claims
 * (role, orgId, organizationId, companyId) in line with users/{uid} when its
 * role or organization/company changes, so the claim-reading callables follow
 * a promotion, demotion, move or removal without a manual script.
 *
 * Trust model: users/{uid} is never proof of a role on its own.
 *   - Only role/scope changes are looked at (scopeOf before != after); any
 *     other edit of the doc does nothing.
 *   - Removing or narrowing is always applied: the doc was deleted, or its
 *     role is no longer staff -> the staff claim keys are removed.
 *   - Granting or changing a claim needs a server-side membership that says
 *     the same thing: organizations/{org}/members/{uid} (org admin, marketing)
 *     or organizations/{org}/companies/{co}/members/{uid} (company roles).
 *     Those docs are written by claimInvite / createAdminUser (Admin SDK), or
 *     by the super admin / the chain's own org admin under the rules. When
 *     nothing confirms the new role or scope, a staff claim the account held
 *     is removed (fail closed) and nothing is granted.
 *   - Global roles (accountant) are never granted here; super-admin and
 *     technical_support claims are never touched (admin web flows own them).
 *   - Delegate claims (delegateLoginV2) are never touched.
 *   - Other claim keys (mfaGraceUntil, impersonation...) are kept.
 * The claims reach the user's ID token on its next refresh (<= 1 hour) or
 * sign-in. Writes only Auth claims, never Firestore, so it cannot loop.
 *
 * Deploy: functions:tashil-mobile-notifications:syncStaffClaimsOnUserWrite
 * Production: only after the users rules from dev (self-update cannot change
 * role/organizationUID/companyUID) are live, and after the backfill.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  Data,
  currentStaffClaims,
  membershipConfirms,
  membershipPaths,
  mergeStaffClaims,
  planStaffClaimSync,
  stripStaffClaims,
} from "./staff_claims_sync_logic";

if (admin.apps.length === 0) admin.initializeApp();

export type SyncResult = "noop" | "granted" | "revoked" | "unverified";

/** Applies one users/{uid} write to the Auth claims. Returns what it did. */
export async function applyStaffClaimSync(
  db: admin.firestore.Firestore,
  auth: admin.auth.Auth,
  uid: string,
  before: Data,
  after: Data,
): Promise<{result: SyncResult; reason: string}> {
  let user: admin.auth.UserRecord;
  try {
    user = await auth.getUser(uid);
  } catch (e) {
    if ((e as {code?: string}).code === "auth/user-not-found") return {result: "noop", reason: "no Auth user"};
    throw e;
  }
  const claims = user.customClaims || {};
  const plan = planStaffClaimSync(before, after, claims);
  if (plan.action === "noop") return {result: "noop", reason: plan.reason};
  if (plan.action === "revoke") {
    await auth.setCustomUserClaims(uid, stripStaffClaims(claims));
    return {result: "revoked", reason: plan.reason};
  }
  const paths = membershipPaths(uid, plan.want);
  const members = await Promise.all(paths.map(async (p) => {
    const s = await db.doc(p).get();
    return s.exists ? s.data() : null;
  }));
  if (members.some((m) => membershipConfirms(m, plan.want))) {
    // Re-read so a claim written meanwhile (e.g. by claimInvite) is merged, not lost.
    const fresh = (await auth.getUser(uid)).customClaims || {};
    await auth.setCustomUserClaims(uid, mergeStaffClaims(fresh, plan.want));
    return {result: "granted", reason: `membership ${paths.join(" or ")}`};
  }
  if (currentStaffClaims(claims)) {
    await auth.setCustomUserClaims(uid, stripStaffClaims(claims));
    return {result: "revoked", reason: "new role/scope not confirmed by a membership"};
  }
  return {result: "unverified", reason: "new role/scope not confirmed by a membership"};
}

export const syncStaffClaimsOnUserWrite = functions
  .region("us-central1")
  .runWith({memory: "256MB", timeoutSeconds: 60})
  .firestore.document("users/{uid}")
  .onWrite(async (change, ctx) => {
    const uid = String(ctx.params.uid);
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    try {
      const r = await applyStaffClaimSync(admin.firestore(), admin.auth(), uid, before, after);
      if (r.result !== "noop") {
        functions.logger.info("staff claims sync", {event: "staff_claims_sync", uid, ...r});
      }
    } catch (e) {
      functions.logger.error("staff claims sync failed", {event: "staff_claims_sync_error", uid,
        code: (e as {code?: string})?.code ?? ""});
    }
  });
