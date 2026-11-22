/**
 * enforceSingleDelegatePublicId (TAS-246): keeps ONE delegatePublicId per
 * delegate on every copy and on users/{uid}. See delegate_public_id_logic.ts.
 *
 * Why on the server: a chain admin approving in the app can only read the
 * copies of its own chain, so the app's cross-chain lookup is denied and a
 * new code used to be allocated for every chain.
 *
 * Writes only delegatePublicId (Admin SDK). Its own writes trigger it again,
 * find every doc equal and stop.
 *
 * Deploy: functions:tashil-mobile-notifications:enforceSingleDelegatePublicId
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  Data,
  formatPublicId,
  planPublicId,
  publicIdCheckNeeded,
} from "./delegate_public_id_logic";

if (admin.apps.length === 0) admin.initializeApp();

type Db = admin.firestore.Firestore;

/** Applies the plan for one delegate. Returns the code written, or "". */
export async function enforceSinglePublicId(db: Db, uid: string): Promise<{code: string; written: number}> {
  const snap = await db.collectionGroup("delegates").where("uid", "==", uid).get();
  const copies = snap.docs
    .filter((d) => d.ref.path.startsWith("organizations/"))
    .map((d) => ({path: d.ref.path, data: d.data() as Data}));
  const userSnap = await db.doc(`users/${uid}`).get();
  const user = userSnap.exists ? {path: userSnap.ref.path, data: userSnap.data() as Data} : null;
  const plan = planPublicId(copies, user);
  if (!plan.paths.length) return {code: plan.canonical, written: 0};

  let code = plan.canonical;
  if (plan.allocate) {
    const counter = db.doc("counters/delegates");
    const n = await db.runTransaction(async (t) => {
      const c = await t.get(counter);
      const next = (Number(c.data()?.count) || 0) + 1;
      t.set(counter, {count: next}, {merge: true});
      return next;
    });
    code = formatPublicId(n);
  }
  if (!code) return {code: "", written: 0};

  const batch = db.batch();
  for (const p of plan.paths) batch.set(db.doc(p), {delegatePublicId: code}, {merge: true});
  await batch.commit();
  return {code, written: plan.paths.length};
}

export const enforceSingleDelegatePublicId = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .firestore.document("organizations/{orgId}/companies/{companyId}/delegates/{uid}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? (change.before.data() as Data) : null;
    const after = change.after.exists ? (change.after.data() as Data) : null;
    if (!publicIdCheckNeeded(before, after)) return null;
    const uid = (typeof after?.uid === "string" && after.uid.trim()) || String(context.params.uid);
    const res = await enforceSinglePublicId(admin.firestore(), uid);
    if (res.written) functions.logger.info("enforceSingleDelegatePublicId", {uid, ...res});
    return null;
  });
