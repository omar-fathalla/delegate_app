import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {phoneQueryVariants} from "./delegate_login_logic";
import {
  Denial,
  callerAllowed,
  emailPatch,
  isDenial,
  parseContactRequest,
  phoneTakenByOther,
} from "./staff_contact_logic";

function fail(d: Denial): never {
  throw new functions.https.HttpsError(d.code, d.message, {reason: d.reason});
}

/**
 * updateOwnStaffContact (TAS-49)
 *
 * { field: "phone", value } — sets users/{uid}.phoneNumber after checking no
 * other users doc holds the number.
 * { field: "email" } — copies the confirmed Firebase Auth email into
 * users/{uid}.email (the app changes the Auth email with
 * verifyBeforeUpdateEmail first).
 *
 * The rules stop clients from writing phoneNumber / phone / email on their
 * own users doc, so deploy this before (or with) those rules:
 *   firebase deploy --project <id> --only functions:tashil-mobile-notifications:updateOwnStaffContact
 */
export const updateOwnStaffContact = functions
  .region("us-central1")
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.", {reason: "unauthenticated"});
    }
    const uid = context.auth.uid;
    const req = parseContactRequest(data);
    if (isDenial(req)) fail(req);

    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();
    const denied = callerAllowed(context.auth.token?.role, snap.exists ? snap.data() : undefined);
    if (denied) fail(denied);

    if (req.field === "email") {
      const authUser = await admin.auth().getUser(uid);
      const patch = emailPatch(authUser.email);
      if (isDenial(patch)) fail(patch);
      await userRef.set({...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      return {ok: true, field: "email", email: patch.email};
    }

    const phone = req.phone as string;
    const holders = await db.collection("users")
      .where("phoneNumber", "in", phoneQueryVariants(phone).slice(0, 10))
      .limit(5)
      .get();
    if (phoneTakenByOther(uid, holders.docs.map((d) => d.id))) {
      fail({code: "already-exists", reason: "phone_taken", message: "This number belongs to another account."});
    }
    await userRef.set({
      phoneNumber: phone,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    functions.logger.info("staff_contact_updated", {uid, field: "phone"});
    return {ok: true, field: "phone", phoneNumber: phone};
  });
