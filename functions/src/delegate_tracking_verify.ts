/**
 * TAS-48: recompute the live tracking verdict on the server.
 *
 * delegate_tracking/{delegateId} is written by the delegate's own app with
 * its own inside/outside verdict. This trigger loads the real branch
 * (organizations/{org}/branches/{id}, then root branches/{id}), computes
 * the distance from the delegate's last position, checks that the written
 * company/organization is the delegate's real membership, and stamps
 * server-only fields (verified*, statusMismatch, scopeMismatch). The rules
 * deny those fields to every client. Old app builds are unaffected.
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:onDelegateTrackingWritten
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  TrackingInputs,
  needsVerification,
  sameInputs,
  trackingInputs,
  verifyTracking,
} from "./delegate_tracking_verify_logic";

if (admin.apps.length === 0) admin.initializeApp();

async function loadBranch(
  db: FirebaseFirestore.Firestore,
  inputs: TrackingInputs,
): Promise<Record<string, unknown> | null> {
  if (!inputs.branchId) return null;
  if (inputs.organizationUID) {
    const nested = await db.collection("organizations").doc(inputs.organizationUID)
      .collection("branches").doc(inputs.branchId).get();
    if (nested.exists) return nested.data() || {};
  }
  // Root branches are written by staff only (TAS-54), so they are trusted
  // whatever organization they carry (the app resolves them the same way).
  const root = await db.collection("branches").doc(inputs.branchId).get();
  return root.exists ? (root.data() || {}) : null;
}

async function loadMembership(
  db: FirebaseFirestore.Firestore,
  delegateId: string,
  inputs: TrackingInputs,
): Promise<Record<string, unknown> | null> {
  if (!inputs.organizationUID || !inputs.companyUID) return null;
  const snap = await db.collection("organizations").doc(inputs.organizationUID)
    .collection("companies").doc(inputs.companyUID)
    .collection("delegates").doc(delegateId).get();
  return snap.exists ? (snap.data() || {}) : null;
}

export const onDelegateTrackingWritten = functions.firestore
  .document("delegate_tracking/{delegateId}")
  .onWrite(async (change, context) => {
    const delegateId = context.params.delegateId as string;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;
    if (!needsVerification(before, after)) return;

    const inputs = trackingInputs(after);
    const db = admin.firestore();
    const [branch, membership] = await Promise.all([
      loadBranch(db, inputs),
      loadMembership(db, delegateId, inputs),
    ]);
    const verdict = verifyTracking({inputs, branch, membership});

    const ref = change.after.ref;
    const written = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      // Deleted meanwhile, or a newer write changed the inputs: that newer
      // event computes its own verdict.
      if (!fresh.exists || !sameInputs(trackingInputs(fresh.data()), inputs)) return false;
      tx.update(ref, {
        ...verdict,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (verdict.statusMismatch || verdict.scopeMismatch) {
      functions.logger.warn("onDelegateTrackingWritten: mismatch", {
        delegateId,
        clientStatus: inputs.clientStatus,
        verifiedStatus: verdict.verifiedStatus,
        verifiedDistanceMeters: verdict.verifiedDistanceMeters,
        reason: verdict.verifiedReason,
        statusMismatch: verdict.statusMismatch,
        scopeMismatch: verdict.scopeMismatch,
        written,
      });
    }
  });
