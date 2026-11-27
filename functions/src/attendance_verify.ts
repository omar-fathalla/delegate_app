/**
 * TAS-361 (phase 1): recompute attendance distances on the server.
 *
 * attendance_logs records are written by the delegate's own app, and the
 * check-out distance check there swallows errors, so a check-out from
 * anywhere passes unmarked. This trigger loads the real branch
 * (organizations/{org}/branches/{id}, then root branches/{id}), computes the
 * distance of the check-in and of the check-out, and stamps server-only
 * fields (verified*, checkOutOutsideBranch, checkOut*). Nothing is rejected,
 * so old app builds keep working. Pure logic: attendance_verify_logic.ts.
 *
 * Deploy (named only, tashil-dev first, prod with the release):
 *   functions:tashil-mobile-notifications:onAttendanceLogWritten,
 *   functions:tashil-mobile-notifications:onOrgAttendanceLogWritten
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  branchRef,
  planVerification,
  verificationUpdate,
} from "./attendance_verify_logic";

if (admin.apps.length === 0) admin.initializeApp();

type Doc = Record<string, unknown> | null | undefined;

async function loadBranch(db: FirebaseFirestore.Firestore, data: Doc): Promise<Doc> {
  const {branchId, organizationUID} = branchRef(data);
  if (!branchId) return null;
  if (organizationUID) {
    const nested = await db.collection("organizations").doc(organizationUID)
      .collection("branches").doc(branchId).get();
    if (nested.exists) return nested.data() || {};
  }
  // Root branches are written by staff only (TAS-54).
  const root = await db.collection("branches").doc(branchId).get();
  return root.exists ? (root.data() || {}) : null;
}

/**
 * Applies the server verdict for one write. Exported for the emulator test.
 * Returns the fields written, or null when nothing needed recomputing.
 */
export async function applyAttendanceVerification(
  db: FirebaseFirestore.Firestore,
  ref: FirebaseFirestore.DocumentReference,
  before: Doc,
  after: Doc,
): Promise<Record<string, unknown> | null> {
  const plan = planVerification(before, after);
  if (!plan.checkIn && !plan.checkOut) return null;

  const branch = await loadBranch(db, after);
  return db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (!fresh.exists) return null;
    // Recompute from the fresh data; a newer write gets its own event too.
    const update = verificationUpdate(fresh.data(), plan, branch);
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (plan.checkIn) update.verifiedAt = now;
    if (plan.checkOut) update.checkOutVerifiedAt = now;
    tx.update(ref, update as FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>);
    return update;
  });
}

async function verifyAttendance(change: functions.Change<functions.firestore.DocumentSnapshot>) {
  const ref = change.after.ref;
  const written = await applyAttendanceVerification(
    admin.firestore(),
    ref,
    change.before.exists ? change.before.data() : null,
    change.after.exists ? change.after.data() : null,
  );
  if (written && written.checkOutOutsideBranch === true) {
    functions.logger.info("attendance: check-out outside the branch", {
      path: ref.path,
      distance: written.checkOutVerifiedDistanceMeters ?? written.verifiedDistanceMeters,
    });
  }
}

export const onAttendanceLogWritten = functions.firestore
  .document("attendance_logs/{logId}")
  .onWrite((change) => verifyAttendance(change));

export const onOrgAttendanceLogWritten = functions.firestore
  .document("organizations/{orgId}/attendance_logs/{logId}")
  .onWrite((change) => verifyAttendance(change));
