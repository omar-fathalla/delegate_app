import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {
  StaffPhonesMintDecision,
  decideStaffPhonesMint,
  mergeStaffPhonesClaims,
  phoneFieldChanged,
  resolveStaffMintPhone,
  shouldProcessStaffUser,
} from "./staff_phones_claim_logic";
import {hasStaffPhoneCollision, readAuthCustomClaims} from "./staff_phones_claim_query";

// The collision check scans every users and delegate doc (phone fields only).
const opts = {timeoutSeconds: 300, memory: "512MB" as const};

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

    let authUser: admin.auth.UserRecord;
    try {
      authUser = await admin.auth().getUser(uid);
    } catch (error) {
      console.error("onStaffUserPhonesClaimSync no auth user", {uid, code: (error as {code?: string}).code});
      return null;
    }

    const mint = resolveStaffMintPhone(authUser.phoneNumber, after.phoneNumber);
    let decision: StaffPhonesMintDecision;
    if (!mint.phone) {
      decision = decideStaffPhonesMint("", false);
    } else {
      let collision = true;
      try {
        collision = await hasStaffPhoneCollision(admin.firestore(), uid, mint.phone);
      } catch (error) {
        console.error("onStaffUserPhonesClaimSync collision lookup failed", {uid});
      }
      decision = decideStaffPhonesMint(mint.phone, collision);
    }
    if (decision.reason === "phone_collision") {
      console.warn("onStaffUserPhonesClaimSync collision", {uid, source: mint.source});
    }

    const merged = mergeStaffPhonesClaims({...(authUser.customClaims || {})}, decision);
    try {
      await admin.auth().setCustomUserClaims(uid, merged);
      console.log("onStaffUserPhonesClaimSync", {
        uid,
        action: decision.action,
        reason: decision.reason,
        source: mint.source,
        variants: decision.phones?.length ?? 0,
      });
    } catch (error) {
      console.error("onStaffUserPhonesClaimSync claims update failed", uid);
    }
    return null;
  });
