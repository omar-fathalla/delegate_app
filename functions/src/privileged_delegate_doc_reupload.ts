/**
 * Callable privilegedReuploadDelegateDocument — SA / technical support
 * approved document replace server-side (Mohamed 2026-11-15).
 *
 * Deploy: functions:tashil-mobile-notifications:privilegedReuploadDelegateDocument
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {
  decidePrivilegedDocReupload,
  isKnownSupervisorReuploadDocType,
  mergePrivilegedReuploadedDocument,
  urlFieldsForDocType,
} from "./privileged_delegate_doc_reupload_logic";

const opts = {timeoutSeconds: 60, memory: "256MB" as const};

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

async function loadCaller(uid: string) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "تعذر التحقق من صلاحيات المستخدم.",
    );
  }
  const d = snap.data() || {};
  return {uid, role: d.role};
}

export const privilegedReuploadDelegateDocument = functions
  .region("us-central1")
  .runWith(opts)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new functions.https.HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً.");
    }
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const delegateUid = str(p.uid);
    const organizationUID = str(p.organizationUID);
    const companyUID = str(p.companyUID);
    const docType = str(p.docType);
    const newUrl = str(p.newUrl);
    if (!delegateUid || !organizationUID || !companyUID || !docType || !newUrl) {
      throw new functions.https.HttpsError("invalid-argument", "بيانات الطلب غير مكتملة.");
    }
    if (!isKnownSupervisorReuploadDocType(docType)) {
      throw new functions.https.HttpsError("invalid-argument", "نوع المستند غير مدعوم.");
    }

    const caller = await loadCaller(ctx.auth.uid);
    const db = admin.firestore();
    const delegateRef = db
    .collection("organizations")
    .doc(organizationUID)
    .collection("companies")
    .doc(companyUID)
    .collection("delegates")
    .doc(delegateUid);
    const snap = await delegateRef.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "لم يتم العثور على المندوب.");
    }
    const delegateData = snap.data() || {};
    const decision = decidePrivilegedDocReupload(
      caller,
      {
        delegateUid,
        organizationUID: str(delegateData.organizationUID ?? delegateData.organizationId),
        companyUID: str(delegateData.companyUID ?? delegateData.companyId),
        status: delegateData.status,
      },
      {organizationUID, companyUID},
    );
    if (!decision.ok) {
      const msg = decision.reason === "caller_not_privileged_staff"
        ? "ليس لديك صلاحية استبدال مستندات المناديب."
        : decision.reason === "out_of_scope"
          ? "المندوب خارج نطاق الشركة أو المؤسسة المحددة."
          : "لا يمكن تعديل مستندات هذا المندوب.";
      throw new functions.https.HttpsError("permission-denied", msg);
    }

    const at = new Date().toISOString();
    const urlFields = urlFieldsForDocType(docType, newUrl);
    const documents = mergePrivilegedReuploadedDocument(
      delegateData.documents,
      docType,
      newUrl,
      at,
      caller.uid,
    );
    const batch = db.batch();
    batch.update(delegateRef, {
      ...urlFields,
      documents,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const reqRef = db.collection("delegate_requests").doc(delegateUid);
    const reqSnap = await reqRef.get();
    if (reqSnap.exists) {
      const reqDocs = mergePrivilegedReuploadedDocument(
        reqSnap.data()?.documents,
        docType,
        newUrl,
        at,
        caller.uid,
      );
      batch.set(
        reqRef,
        {
          ...urlFields,
          documents: reqDocs,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    if (docType === "personalPhoto") {
      batch.set(
        db.collection("users").doc(delegateUid),
        {
          photoURL: newUrl,
          profileImageUrl: newUrl,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    await batch.commit();
    return {ok: true, documentStatus: "approved"};
  });