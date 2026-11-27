/**
 * Callable privilegedReuploadDelegateDocument — SA / technical support
 * approved document replace + pending doc review server-side (Mohamed 2026-11-15).
 *
 * Deploy: functions:tashil-mobile-notifications:privilegedReuploadDelegateDocument
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {idReviewRestoresActive} from "./supervisor_delegate_doc_reupload_logic";
import {
  applyPrivilegedDocumentReview,
  decidePrivilegedDocReupload,
  isKnownSupervisorReuploadDocType,
  mergePrivilegedReuploadedDocument,
  resolveReuploadObject,
} from "./privileged_delegate_doc_reupload_logic";
import {refFieldsForDocType} from "./delegate_doc_ref_fields";
import {claimBackedCaller} from "./staff_claims";

const opts = {timeoutSeconds: 60, memory: "256MB" as const};

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function storageErrorMessage(reason: string): string {
  switch (reason) {
    case "invalid_image_url":
    case "invalid_storage_url":
      return "رابط المستند غير صالح أو غير مسموح.";
    case "wrong_delegate_folder":
    case "path_traversal":
    case "invalid_storage_path":
    case "url_path_mismatch":
      return "مسار الملف لا يخص هذا المندوب.";
    case "wrong_bucket":
      return "رابط المستند من خارج تخزين التطبيق.";
    case "object_not_found":
      return "الملف غير موجود في التخزين. أعد الرفع ثم حاول مرة أخرى.";
    default:
      return "تعذر التحقق من ملف المستند.";
  }
}

async function loadCaller(uid: string, token: unknown) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "تعذر التحقق من صلاحيات المستخدم.",
    );
  }
  // TAS-23: role and scope from the token claims, not the users doc.
  const d = claimBackedCaller(snap.data(), token);
  return {uid, role: d.role};
}

async function assertStorageObjectExists(objectPath: string) {
  const bucket = admin.storage().bucket();
  const file = bucket.file(objectPath);
  try {
    await file.getMetadata();
  } catch {
    const [exists] = await file.exists();
    if (!exists) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        storageErrorMessage("object_not_found"),
      );
    }
  }
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
    const reviewMode = typeof p.approve === "boolean";
    const newUrl = str(p.newUrl);
    // TAS-331: the Storage path of the uploaded file (new clients).
    const newPath = str(p.newPath);
    if (!delegateUid || !organizationUID || !companyUID || !docType) {
      throw new functions.https.HttpsError("invalid-argument", "بيانات الطلب غير مكتملة.");
    }
    if (!isKnownSupervisorReuploadDocType(docType)) {
      throw new functions.https.HttpsError("invalid-argument", "نوع المستند غير مدعوم.");
    }
    if (!reviewMode && !newUrl && !newPath) {
      throw new functions.https.HttpsError("invalid-argument", "بيانات الطلب غير مكتملة.");
    }

    const caller = await loadCaller(ctx.auth.uid, ctx.auth.token);
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

    if (reviewMode) {
      const approve = p.approve as boolean;
      const rejectionReason = str(p.rejectionReason);
      if (!approve && !rejectionReason) {
        throw new functions.https.HttpsError("invalid-argument", "سبب الرفض مطلوب.");
      }
      const review = applyPrivilegedDocumentReview(
        delegateData.documents,
        docType,
        approve,
        caller.uid,
        rejectionReason || undefined,
        at,
      );
      if (!review.ok) {
        const reviewMsg = review.reason === "not_found"
          ? "لم يتم العثور على المستند."
          : review.reason === "already_approved"
            ? "هذا المستند معتمد مسبقاً."
            : "لا يمكن مراجعة هذا المستند في حالته الحالية.";
        const code = review.reason === "not_found" ? "not-found" : "failed-precondition";
        throw new functions.https.HttpsError(code, reviewMsg);
      }
      // TAS-373: approving the ID card a supervisor replaced restores the
      // delegate; a rejection leaves it pending with its reason.
      const restore = approve && idReviewRestoresActive(delegateData, review.documents);
      const batch = db.batch();
      batch.update(delegateRef, {
        documents: review.documents,
        ...(restore ? {status: "active", statusReason: FieldValue.delete()} : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
      const reqRef = db.collection("delegate_requests").doc(delegateUid);
      const reqSnap = await reqRef.get();
      if (reqSnap.exists) {
        const reqReview = applyPrivilegedDocumentReview(
          reqSnap.data()?.documents,
          docType,
          approve,
          caller.uid,
          rejectionReason || undefined,
          at,
        );
        if (reqReview.ok) {
          batch.set(reqRef, {
            documents: reqReview.documents,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }
      await batch.commit();
      return {
        ok: true,
        documentStatus: approve ? "approved" : "rejected",
        ...(restore ? {delegateStatus: "active"} : {}),
      };
    }

    const defaultBucket = admin.storage().bucket().name;
    const resolved = resolveReuploadObject(
      newUrl,
      newPath,
      delegateUid,
      defaultBucket,
    );
    if (!resolved.ok) {
      throw new functions.https.HttpsError("invalid-argument", storageErrorMessage(resolved.reason));
    }
    await assertStorageObjectExists(resolved.objectPath);

    const refFields = refFieldsForDocType(docType, newUrl, newPath);
    const documents = mergePrivilegedReuploadedDocument(
      delegateData.documents,
      docType,
      newUrl,
      at,
      caller.uid,
      newPath,
    );
    const batch = db.batch();
    batch.update(delegateRef, {
      ...refFields,
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
        newPath,
      );
      batch.set(
        reqRef,
        {
          ...refFields,
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
          profileImagePath: newPath || FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    await batch.commit();
    return {ok: true, documentStatus: "approved"};
  });