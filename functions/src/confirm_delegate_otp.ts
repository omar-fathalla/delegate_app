import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {decideConfirmDelegateOtp} from "./delegate_login_logic";

/**
 * confirmDelegateOtp
 *
 * After the client links a Firebase Phone Auth credential to the custom-token
 * delegate user, this callable checks Admin Auth for a phoneNumber that matches
 * the phones claim from delegateLoginV2, then sets otp_verified=true.
 *
 * Deploy with:
 *   firebase deploy --only functions:tashil-mobile-notifications:confirmDelegateOtp
 *
 * Does not deploy Firestore rules. Clients must call getIdToken(true) after a
 * successful response so rules see the updated claim.
 */
export const confirmDelegateOtp = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 15, memory: "256MB"})
  .https.onCall(async (_data, context) => {
    try {
      return await handleConfirmDelegateOtp(context);
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("confirmDelegateOtp failed");
      throw new functions.https.HttpsError(
        "internal",
        "Phone confirmation is temporarily unavailable.",
        {reason: "unavailable"},
      );
    }
  });

async function handleConfirmDelegateOtp(
  context: functions.https.CallableContext,
): Promise<{ok: true; otpVerified: true}> {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in before confirming the phone.",
      {reason: "not_signed_in"},
    );
  }

  const uid = context.auth.uid;
  let user: admin.auth.UserRecord;
  try {
    user = await admin.auth().getUser(uid);
  } catch (error) {
    console.error("confirmDelegateOtp getUser failed", uid);
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in before confirming the phone.",
      {reason: "not_signed_in"},
    );
  }

  const decision = decideConfirmDelegateOtp({
    authPhone: user.phoneNumber,
    claims: (user.customClaims || {}) as Record<string, unknown>,
  });

  if (!decision.ok) {
    const map: Record<string, {code: functions.https.FunctionsErrorCode; message: string}> = {
      not_signed_in: {
        code: "unauthenticated",
        message: "Sign in before confirming the phone.",
      },
      not_delegate: {
        code: "permission-denied",
        message: "Only a delegate session can confirm OTP.",
      },
      phone_not_linked: {
        code: "failed-precondition",
        message: "Link a phone number before confirming OTP.",
      },
      phone_mismatch: {
        code: "permission-denied",
        message: "The linked phone does not match this delegate.",
      },
    };
    const mapped = map[decision.reason];
    throw new functions.https.HttpsError(mapped.code, mapped.message, {
      reason: decision.reason,
    });
  }

  try {
    await admin.auth().setCustomUserClaims(uid, decision.nextClaims);
  } catch (error) {
    console.error("confirmDelegateOtp claims update failed", uid);
    throw new functions.https.HttpsError(
      "internal",
      "Phone confirmation is temporarily unavailable.",
      {reason: "unavailable"},
    );
  }

  console.log("confirmDelegateOtp success", {uid});
  return {ok: true, otpVerified: true};
}
