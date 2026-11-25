/**
 * Callable supervisorReuploadDelegateDocument — supervisor active→pending doc
 * replace server-side (Mohamed 2026-11-15 / expression-budget).
 *
 * Deploy: functions:tashil-mobile-notifications:supervisorReuploadDelegateDocument
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {
  decideSupervisorDocReupload,
  isKnownSupervisorReuploadDocType,
  mergeReuploadedDocument,
} from "./supervisor_delegate_doc_reupload_logic";
import {validateDelegateDocumentObjectPath} from "./privileged_delegate_doc_reupload_logic";
import {refFieldsForDocType} from "./delegate_doc_ref_fields";

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

export const supervisorReuploadDelegateDocument = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new functions.https.HttpsError("unauthenticated", "sign_in_required");
    }
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const delegateUid = str(p.uid);
    const docType = str(p.docType);
    const newUrl = str(p.newUrl);
    // TAS-331: the Storage path of the uploaded file (new clients); it must
    // be inside this delegate's own delegate_documents folder.
    const newPath = str(p.newPath);
    if (!delegateUid || !docType || (!newUrl && !newPath)) {
      throw new functions.https.HttpsError("invalid-argument", "missing_fields");
    }
    if (newPath && (/^[a-z]+:/i.test(newPath) ||
        !validateDelegateDocumentObjectPath(newPath, delegateUid).ok)) {
      throw new functions.https.HttpsError("invalid-argument", "invalid_storage_path");
    }
    if (!isKnownSupervisorReuploadDocType(docType)) {
      throw new functions.https.HttpsError("invalid-argument", "unknown_doc_type");
    }

    const caller = await loadCaller(ctx.auth.uid);
    const callerOrg = str(caller.organizationUID);
    const callerCo = str(caller.companyUID);
    if (!callerOrg || !callerCo) {
      throw new functions.https.HttpsError("permission-denied", "out_of_scope");
    }

    const db = admin.firestore();
    const delegateRef = db
      .collection("organizations")
      .doc(callerOrg)
      .collection("companies")
      .doc(callerCo)
      .collection("delegates")
      .doc(delegateUid);
    const snap = await delegateRef.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "delegate_not_found");
    }
    const delegateData = snap.data() || {};
    const delegateOrg = str(delegateData.organizationUID ?? delegateData.organizationId);
    const delegateCo = str(delegateData.companyUID ?? delegateData.companyId);
    const decision = decideSupervisorDocReupload(caller, {
      delegateUid,
      organizationUID: delegateOrg || callerOrg,
      companyUID: delegateCo || callerCo,
      status: delegateData.status,
    });
    if (!decision.ok) {
      throw new functions.https.HttpsError("permission-denied", decision.reason);
    }

    const at = new Date().toISOString();
    const refFields = refFieldsForDocType(docType, newUrl, newPath);
    const documents = mergeReuploadedDocument(delegateData.documents, docType, newUrl, at, newPath);
    const batch = db.batch();
    batch.update(delegateRef, {
      ...refFields,
      status: "pending",
      documents,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const reqRef = db.collection("delegate_requests").doc(delegateUid);
    const reqSnap = await reqRef.get();
    if (reqSnap.exists) {
      const reqDocs = mergeReuploadedDocument(reqSnap.data()?.documents, docType, newUrl, at, newPath);
      batch.set(reqRef, {
        ...refFields,
        documents: reqDocs,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    if (docType === "personalPhoto") {
      batch.set(
        db.collection("users").doc(delegateUid),
        {
          photoURL: newUrl,
          profileImageUrl: newUrl,
          profileImagePath: newPath || FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    await batch.commit();
    return {ok: true, status: "pending"};
  });