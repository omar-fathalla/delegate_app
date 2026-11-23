import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {hasDelegateIdentity, isDeletedDelegateStatus, planDeletedLinkCleanup} from "./delegate_identity";
import {stableDelegateAuthUid} from "./delegate_login_logic";

const DEVICE_BINDINGS = "deviceBindings";
const UNBIND_REQUESTS = "device_unbind_requests";

/**
 * When a delegate link doc is deleted (HR web delete approval, admin cleanup,
 * or the ghost cleanup script) and the delegate has no other live link, clear
 * what lets the deleted delegate keep signing in:
 *   - deviceBindings/{authUid}            (server device binding)
 *   - open device_unbind_requests         (status -> cancelled)
 *   - Firebase refresh tokens + claims    (delegateLoginV2 sessions)
 * A staff account whose uid had a ghost doc is never revoked.
 *
 * Deploy by name only:
 *   firebase deploy --only functions:tashil-mobile-notifications:onDelegateLinkDeleted
 */
export const onDelegateLinkDeleted = functions.firestore
  .document("organizations/{orgId}/companies/{companyId}/delegates/{delegateId}")
  .onDelete(async (snap, context) => {
    const delegateId = String(context.params.delegateId || "");
    if (!delegateId) return null;
    const db = admin.firestore();
    try {
      const remainingLiveLinks = await countRemainingLiveLinks(db, delegateId, snap.ref.path, snap.data() || {});
      const userSnap = await db.collection("users").doc(delegateId).get();
      const usersRole = userSnap.exists ? String(userSnap.get("role") ?? "") : null;
      const plan = planDeletedLinkCleanup({remainingLiveLinks, usersRole});
      functions.logger.info("onDelegateLinkDeleted", {
        path: snap.ref.path, reason: plan.reason, remainingLiveLinks,
      });
      if (plan.reason !== "no_links_left") return null;

      const authUid = stableDelegateAuthUid(delegateId);
      if (plan.clearDeviceBinding) {
        await db.collection(DEVICE_BINDINGS).doc(authUid).delete();
      }
      if (plan.cancelUnbindRequests) {
        const open = await db.collection(UNBIND_REQUESTS)
          .where("delegateUid", "==", delegateId).limit(50).get();
        const batch = db.batch();
        let n = 0;
        for (const doc of open.docs) {
          const status = String(doc.get("status") ?? "");
          if (status !== "pending" && status !== "approved") continue;
          batch.update(doc.ref, {
            status: "cancelled",
            cancelledReason: "delegate_deleted",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          n++;
        }
        if (n > 0) await batch.commit();
      }
      if (plan.deleteUsersDoc) {
        // Re-read inside a transaction: delete only if it is still a
        // delegate-role doc (a staff role written meanwhile is kept).
        await db.runTransaction(async (tx) => {
          const ref = db.collection("users").doc(delegateId);
          const cur = await tx.get(ref);
          if (!cur.exists) return;
          const again = planDeletedLinkCleanup({remainingLiveLinks: 0, usersRole: String(cur.get("role") ?? "")});
          if (again.deleteUsersDoc) tx.delete(ref);
        });
      }
      if (plan.revokeSessions) {
        try {
          // Only undo what delegateLoginV2 set: never touch an auth user
          // whose claims are not delegate claims (staff/admin accounts,
          // including ones with no users/{uid} doc).
          const user = await admin.auth().getUser(authUid);
          if (user.customClaims?.role !== "delegate") {
            functions.logger.info("onDelegateLinkDeleted skip revoke: not a delegate token", {
              path: snap.ref.path,
            });
          } else {
            await admin.auth().setCustomUserClaims(authUid, null);
            await admin.auth().revokeRefreshTokens(authUid);
          }
        } catch (error) {
          const code = (error as {code?: unknown})?.code;
          if (code !== "auth/user-not-found") throw error;
        }
      }
      return null;
    } catch (error) {
      functions.logger.error("onDelegateLinkDeleted failed", {
        path: snap.ref.path, message: String(error),
      });
      throw error;
    }
  });

/**
 * Other link docs for this id that still look like a real, non-deleted
 * delegate. Found by the `uid` field (collection-group index) and, when the
 * deleted doc had a phone, by phone too, in case an older copy has no `uid`.
 */
async function countRemainingLiveLinks(
  db: admin.firestore.Firestore,
  delegateId: string,
  deletedPath: string,
  deletedData: Record<string, unknown>,
): Promise<number> {
  const live = new Set<string>();
  const consider = (doc: admin.firestore.QueryDocumentSnapshot) => {
    if (doc.id !== delegateId || doc.ref.path === deletedPath) return;
    if (!hasDelegateIdentity(doc.data()) || isDeletedDelegateStatus(doc.get("status"))) return;
    live.add(doc.ref.path);
  };
  const byUid = await db.collectionGroup("delegates").where("uid", "==", delegateId).get();
  byUid.docs.forEach(consider);
  const phone = typeof deletedData.phoneNumber === "string" ? deletedData.phoneNumber.trim() : "";
  if (phone) {
    const byPhone = await db.collectionGroup("delegates").where("phoneNumber", "==", phone).limit(50).get();
    byPhone.docs.forEach(consider);
  }
  return live.size;
}
