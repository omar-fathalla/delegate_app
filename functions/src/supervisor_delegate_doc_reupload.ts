/**
 * Callable supervisorReuploadDelegateDocument — supervisor active→pending doc
 * replace server-side (Mohamed 2026-11-15 / expression-budget).
 *
 * Deploy: functions:tashil-mobile-notifications:supervisorReuploadDelegateDocument
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  decideSupervisorDocReupload,
  mergeReuploadedDocument,
  urlFieldsForDocType,
} from "./supervisor_delegate_doc_reupload_logic";

if (admin.apps.length === 0) admin.initializeApp();

const opts = {timeoutSeconds: 60, memory: "256MB" as const};

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

async function loadCaller(uid: string) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) throw new functions.https.HttpsError("permission-denied", "caller_not_staff");
  const d = snap.data() || {};
  return {
    uid,
    role: d.role,
    organizationUID: d.organizationUID,
    companyUID: d.companyUID,
  };
}

async function delegateSnapshots(
  db: FirebaseFirestore.Firestore,
  delegateUid: string,
  companyUID: string,
): Promise<FirebaseFirestore.DocumentSnapshot[]> {
  const orgs = await db.collection("organizations").get();
  const out: FirebaseFirestore.DocumentSnapshot[] = [];
  for (const org of orgs.docs) {
    const ref = org.ref.collection("companies").doc(companyUID).collection("delegates").doc(delegateUid);
    const snap = await ref.get();
    if (snap.exists) out.push(snap);
  }
  return out;
}

export const supervisorReuploadDelegateDocument = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new functions.https.HttpsError("unauthenticated", "sign_in_required");
    }
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const delegateUid = str(p.uid);
    const organizationUID = str(p.organizationUID);
    const companyUID = str(p.companyUID);
    const docType = str(p.docType);
    const newUrl = str(p.newUrl);
    if (!delegateUid || !organizationUID || !companyUID || !docType || !newUrl) {
      throw new functions.https.HttpsError("invalid-argument", "missing_fields");
    }

    const caller = await loadCaller(ctx.auth.uid);
    const db = admin.firestore();
    const snaps = await delegateSnapshots(db, delegateUid, companyUID);
    if (snaps.length === 0) {
      throw new functions.https.HttpsError("not-found", "delegate_not_found");
    }
    const primary = snaps[0].data() || {};
    const decision = decideSupervisorDocReupload(caller, {
      delegateUid,
      organizationUID,
      companyUID,
      status: primary.status,
    });
    if (!decision.ok) {
      throw new functions.https.HttpsError("permission-denied", decision.reason);
    }

    const at = new Date().toISOString();
    const urlFields = urlFieldsForDocType(docType, newUrl);
    const batch = db.batch();
    for (const snap of snaps) {
      const documents = mergeReuploadedDocument(snap.data()?.documents, docType, newUrl, at);
      batch.update(snap.ref, {
        ...urlFields,
        status: "pending",
        documents,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const reqRef = db.collection("delegate_requests").doc(delegateUid);
    const reqSnap = await reqRef.get();
    if (reqSnap.exists) {
      const documents = mergeReuploadedDocument(reqSnap.data()?.documents, docType, newUrl, at);
      batch.set(reqRef, {
        ...urlFields,
        documents,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    if (docType === "personalPhoto") {
      batch.set(
        db.collection("users").doc(delegateUid),
        {
          photoURL: newUrl,
          profileImageUrl: newUrl,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    await batch.commit();
    return {ok: true, status: "pending"};
  });