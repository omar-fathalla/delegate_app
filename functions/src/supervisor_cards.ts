import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {SUPERVISOR_POSITIONS, cardsFrom, isDenial, parseScope} from "./supervisor_cards_logic";
import {callerDelegateId} from "./caller_delegate_id";

/**
 * getMySupervisorCards (TAS-55)
 *
 * The rules no longer let a delegate read the other delegate documents of
 * its company (national ID, phone, document URLs). The home screen's
 * supervisor card gets the supervisors' name, phone, email and photo from
 * here instead. Request: { organizationUID?, companyUID? } (defaults to the
 * token's orgId / companyId). Response: { supervisors: SupervisorCard[] }.
 *
 *   firebase deploy --project <id> --only functions:tashil-mobile-notifications:getMySupervisorCards
 */
export const getMySupervisorCards = functions
  .region("us-central1")
  .https.onCall(async (data: unknown, context) => {
    const scope = parseScope(data, context.auth?.token as Record<string, unknown> | undefined);
    if (isDenial(scope)) {
      throw new functions.https.HttpsError(scope.code, scope.message, {reason: scope.reason});
    }
    const snap = await admin.firestore()
      .collection("organizations").doc(scope.organizationUID)
      .collection("companies").doc(scope.companyUID)
      .collection("delegates")
      .where("position", "in", SUPERVISOR_POSITIONS)
      .limit(20)
      .get();
    const supervisors = cardsFrom(
      // TAS-28 phase 0: skip the caller's own card by its delegateId claim.
      callerDelegateId(context.auth?.uid, context.auth?.token as Record<string, unknown> | undefined),
      snap.docs.map((d) => ({id: d.id, data: d.data()})),
    );
    return {supervisors};
  });
