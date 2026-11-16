import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  decideStaffPhonesMint,
  mergeStaffPhonesClaims,
  phoneFieldChanged,
  shouldProcessStaffUser,
} from "./staff_phones_claim_logic";
import {hasStaffPhoneCollision, readAuthCustomClaims} from "./staff_phones_claim_query";

const opts = {timeoutSeconds: 60, memory: "256MB" as const};

/**
 * Re-mints staff JWT `phones` when users/{uid}.phoneNumber changes.
 *
 * Deploy (additive, isolated codebase only):
 *   firebase deploy --only functions:tashil-mobile-notifications:onStaffUserPhonesClaimSync
 */
export const onStaffUserPhonesClaimSync = functions
  .region("us-central1")
  .runWith(opts)
  .firestore.document("users/{uid}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const after = change.after.exists ? (change.after.data() as Record<string, unknown>) : undefined;
    const before = change.before.exists ? (change.before.data() as Record<string, unknown>) : undefined;

    if (!after) {
      if (shouldProcessStaffUser(before)) {
        const existing = await readAuthCustomClaims(uid);
        const merged = mergeStaffPhonesClaims(existing, {action: "clear", reason: "user_deleted"});
        await admin.auth().setCustomUserClaims(uid, merged);
      }
      return null;
    }

    if (!shouldProcessStaffUser(after)) return null;

    const isCreate = !change.before.exists;
    if (!isCreate && !phoneFieldChanged(before, after)) return null;

    const phoneRaw = after.phoneNumber;
    const trustedAdminWrite = after.updatedBy !== uid &&
      typeof after.updatedBy === "string" &&
      after.updatedBy.length > 0;

    let collision = false;
    if (typeof phoneRaw === "string" && phoneRaw.trim()) {
      collision = await hasStaffPhoneCollision(admin.firestore(), uid, phoneRaw);
    }

    const decision = decideStaffPhonesMint(phoneRaw, collision, trustedAdminWrite);
    if (decision.action === "skip") {
      console.warn("onStaffUserPhonesClaimSync skipped", {uid, reason: decision.reason});
      return null;
    }

    const existing = await readAuthCustomClaims(uid);
    const merged = mergeStaffPhonesClaims(existing, decision);
    try {
      await admin.auth().setCustomUserClaims(uid, merged);
      console.log("onStaffUserPhonesClaimSync", {
        uid,
        action: decision.action,
        variants: decision.phones?.length ?? 0,
      });
    } catch (error) {
      console.error("onStaffUserPhonesClaimSync claims update failed", uid);
    }
    return null;
  });