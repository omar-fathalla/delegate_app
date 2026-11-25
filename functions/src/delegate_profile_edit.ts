import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  isValidEgyptianNationalId,
  isValidEgyptianPhone,
  normalizeEgyptianPhone,
  normalizeIdDigits,
} from "./check_delegate_duplicate_logic";
import {findDuplicatePublic} from "./check_delegate_duplicate_query";
import {
  applyProfileFields,
  assertImageFields,
  auditDoc,
  fieldArabicLabel,
  imageRef,
  isImageField,
  isEditableDelegateStatus,
  isEditableRequestStatus,
  canCallEditDelegateProfile,
  profileEditCompanyScope,
  isPatchableTarget,
  isReviewerRole,
  privilegedAlertDoc,
  ProfileEditInput,
  sanitizeProfileEdit,
  shouldAlertAdmins,
  supervisorReviewAlertDoc,
  uniqueRecipientIds,
  valueOf,
  PRIVILEGED_ALERT_ROLE_VALUES,
  classifyReviewTarget,
  usersProfileSyncPatch,
  reviewerIsSubmitter,
  nationalIdFieldsForApprovedReview,
} from "./delegate_profile_edit_logic";
import {claimBackedCaller} from "./staff_claims";

function asUpdate(patch: Record<string, unknown>): FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> {
  return patch as FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>;
}

const REGION = "us-central1";
const AUDIT = "delegate_profile_audit_logs";

function requireAuth(context: functions.https.CallableContext): string {
  if (!context.auth || context.auth.token.firebase?.sign_in_provider === "anonymous") {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  return context.auth.uid;
}

async function loadCaller(db: FirebaseFirestore.Firestore, uid: string, token: unknown) {
  const snap = await db.collection("users").doc(uid).get();
  // TAS-23: role and scope from the token claims, not the users doc.
  const data = claimBackedCaller(snap.data(), token);
  return {
    uid,
    role: String(data.role || ""),
    name: String(data.fullName || data.displayName || data.name || "").trim(),
    companyUID: String(data.companyUID || data.companyId || "").trim(),
    organizationUID: String(data.organizationUID || data.organizationId || "").trim(),
  };
}

function throwIfDuplicate(result: {duplicate: boolean; reason?: string; companyName?: string}, kind: "phone" | "nationalId") {
  if (!result.duplicate) return;
  if (result.reason === "another_company") {
    const name = result.companyName || "";
    const msg = kind === "phone"
      ? (name
        ? `رقم الموبايل مسجل بالفعل في شركة: ${name}. يرجى حذفه منها أولاً.`
        : "رقم الموبايل مسجل بالفعل في شركة أخرى. يرجى حذفه منها أولاً.")
      : (name
        ? `مسجل بالفعل في شركة: ${name}. يرجى حذفه منها أولاً.`
        : "الرقم القومي مسجل بالفعل في شركة أخرى. يرجى حذفه منها أولاً.");
    throw new functions.https.HttpsError("already-exists", msg, result);
  }
  const msg = kind === "phone"
    ? "رقم الموبايل مسجل بالفعل لمندوب أو طلب آخر في شركتك."
    : "الرقم القومي مسجل بالفعل لمندوب أو طلب آخر في شركتك.";
  throw new functions.https.HttpsError("already-exists", msg, result);
}

interface Target {
  kind: "delegate" | "request";
  ref: FirebaseFirestore.DocumentReference;
  data: FirebaseFirestore.DocumentData;
}

async function collectTargets(
  db: FirebaseFirestore.Firestore,
  opts: {companyUID: string; delegateUid?: string; requestId?: string},
): Promise<{targets: Target[]; delegateUid: string; companyName: string; organizationUID: string; displayName: string}> {
  const targets: Target[] = [];
  const seen = new Set<string>();
  const add = (kind: Target["kind"], snap: FirebaseFirestore.DocumentSnapshot) => {
    if (!snap.exists) return;
    const data = snap.data() || {};
    if (!isPatchableTarget(opts.companyUID, data, snap.ref.path)) return;
    if (seen.has(snap.ref.path)) return;
    seen.add(snap.ref.path);
    targets.push({kind, ref: snap.ref, data});
  };

  let delegateUid = String(opts.delegateUid || "").trim();
  const requestId = String(opts.requestId || "").trim();
  let companyName = "";
  let organizationUID = "";
  let displayName = "";

  if (requestId) {
    const req = await db.collection("delegate_requests").doc(requestId).get();
    if (!req.exists) {
      throw new functions.https.HttpsError("not-found", "الطلب غير موجود.");
    }
    add("request", req);
    const data = req.data() || {};
    if (!delegateUid) {
      delegateUid = String(data.existingDelegateUid || data.delegateUid || data.uid || req.id).trim();
    }
    companyName = String(data.companyName || "").trim();
    organizationUID = String(data.organizationUID || data.organizationId || "").trim();
    displayName = String(data.fullName || "").trim();
  }

  if (delegateUid) {
    const byUid = await db.collectionGroup("delegates").where("uid", "==", delegateUid).get();
    for (const doc of byUid.docs) add("delegate", doc);
    const reqs = await db.collection("delegate_requests")
      .where("existingDelegateUid", "==", delegateUid).get();
    for (const doc of reqs.docs) add("request", doc);
    const reqs2 = await db.collection("delegate_requests")
      .where("delegateUid", "==", delegateUid).get();
    for (const doc of reqs2.docs) add("request", doc);
    const selfReq = await db.collection("delegate_requests").doc(delegateUid).get();
    if (selfReq.exists) add("request", selfReq);
  }

  if (!targets.length) {
    throw new functions.https.HttpsError("not-found", "لم يتم العثور على المندوب.");
  }

  // Prefer a live delegate doc for metadata
  const live = targets.find((t) => t.kind === "delegate") || targets[0];
  companyName = companyName || String(live.data.companyName || "").trim();
  organizationUID = organizationUID
    || String(live.data.organizationUID || live.data.organizationId || "").trim();
  displayName = displayName || String(live.data.fullName || "").trim();
  if (!delegateUid) {
    delegateUid = String(live.data.uid || live.data.existingDelegateUid || live.ref.id).trim();
  }
  return {targets, delegateUid, companyName, organizationUID, displayName};
}

async function notifyPrivileged(
  db: FirebaseFirestore.Firestore,
  opts: {
    title: string;
    body: string;
    type: string;
    senderName: string;
    senderRole: string;
    companyUID: string;
    organizationUID: string;
    requestId?: string;
    delegateUid?: string;
  },
) {
  let recipientIds: string[] = [];
  try {
    const users = await db.collection("users").where("role", "in", [
      ...PRIVILEGED_ALERT_ROLE_VALUES,
    ]).get();
    recipientIds = uniqueRecipientIds(users.docs.map((d) => d.id));
  } catch (err) {
    functions.logger.warn("privileged user query failed; skipping alerts", err);
    return;
  }
  if (!recipientIds.length) return;
  const batch = db.batch();
  for (const recipientUid of recipientIds) {
    const ref = db.collection("notifications").doc();
    batch.set(ref, {
      ...privilegedAlertDoc({
        recipientUid,
        title: opts.title,
        body: opts.body,
        type: opts.type,
        senderName: opts.senderName,
        senderRole: opts.senderRole,
        companyUID: opts.companyUID,
        organizationUID: opts.organizationUID,
        requestId: opts.requestId,
        targetDelegateUid: opts.delegateUid,
      }),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

function writeAudits(
  batch: FirebaseFirestore.WriteBatch,
  db: FirebaseFirestore.Firestore,
  drafts: ReturnType<typeof auditDoc>[],
) {
  for (const rec of drafts) {
    const ref = db.collection(AUDIT).doc();
    batch.set(ref, {
      ...rec,
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

/**
 * editDelegateProfile (company supervisor / company-admin, super-admin, tech support)
 * Input: { companyUID, delegateUid?, requestId?, fullName?, phoneNumber?,
 *          personalPhotoURL?, nationalIdFrontUrl?, nationalIdBackUrl? }
 * Updates live delegate docs in every chain of the company and keeps open
 * delegate_requests in sync. Phone changes go through the duplicate check.
 */
export const editDelegateProfile = functions
  .region(REGION)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    const uid = requireAuth(context);
    const db = admin.firestore();
    const caller = await loadCaller(db, uid, context.auth?.token);
    if (!canCallEditDelegateProfile(caller.role)) {
      throw new functions.https.HttpsError("permission-denied", "غير مسموح.");
    }
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const companyUID = typeof payload.companyUID === "string" ? payload.companyUID.trim() : "";
    if (!companyUID) {
      throw new functions.https.HttpsError("invalid-argument", "companyUID مطلوب.");
    }
    const scope = profileEditCompanyScope(caller.role, caller.companyUID, companyUID);
    if (scope !== "ok") {
      throw new functions.https.HttpsError("permission-denied", "غير مسموح.");
    }
    const {fields, keys} = sanitizeProfileEdit(payload as ProfileEditInput);
    if (!keys.length) {
      throw new functions.https.HttpsError("invalid-argument", "لا توجد حقول للتعديل.");
    }
    const delegateUidIn = typeof payload.delegateUid === "string" ? payload.delegateUid.trim() : "";
    const requestIdIn = typeof payload.requestId === "string" ? payload.requestId.trim() : "";
    if (!delegateUidIn && !requestIdIn) {
      throw new functions.https.HttpsError("invalid-argument", "delegateUid أو requestId مطلوب.");
    }

    const collected = await collectTargets(db, {
      companyUID,
      delegateUid: delegateUidIn,
      requestId: requestIdIn,
    });
    try {
      assertImageFields(fields, collected.delegateUid);
    } catch (err) {
      throw new functions.https.HttpsError("invalid-argument", "رابط الصورة غير صالح.");
    }

    const editable: Target[] = [];
    for (const t of collected.targets) {
      const st = t.data.status;
      if (t.kind === "request") {
        if (String(t.ref.id) === requestIdIn && !isEditableRequestStatus(st)) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "يمكن تعديل الطلبات المعلقة أو التي تحتاج إجراء فقط.",
          );
        }
        if (isEditableRequestStatus(st)) editable.push(t);
      } else if (isEditableDelegateStatus(st)) {
        editable.push(t);
      }
    }
    if (!editable.length) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "لا توجد سجلات قابلة للتعديل لهذه الحالة.",
      );
    }

    if (fields.phoneNumber) {
      if (!isValidEgyptianPhone(fields.phoneNumber)) {
        throw new functions.https.HttpsError("invalid-argument", "رقم الموبايل غير صالح.");
      }
      const phone = normalizeEgyptianPhone(fields.phoneNumber);
      fields.phoneNumber = phone;
      const dup = await findDuplicatePublic(db, {
        phoneNumber: phone,
        companyUID,
        excludeDelegateUid: collected.delegateUid,
      });
      throwIfDuplicate(dup, "phone");
    }

    const before = editable[0].data as Record<string, unknown>;
    const audits = keys.map((field) => auditDoc({
      actorUid: caller.uid,
      actorName: caller.name,
      actorRole: caller.role,
      field,
      oldValue: valueOf(before, field),
      newValue: isImageField(field) ? imageRef(fields, field) : String(fields[field] || ""),
      delegateUid: collected.delegateUid,
      delegateName: String(fields.fullName || collected.displayName || ""),
      companyUID,
      companyName: collected.companyName,
      organizationUID: collected.organizationUID,
      source: "direct_edit",
      requestId: requestIdIn || undefined,
    }));

    const batch = db.batch();
    for (const t of editable) {
      const patch = applyProfileFields(t.data as Record<string, unknown>, fields);
      patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.update(t.ref, asUpdate(patch));
    }
    writeAudits(batch, db, audits);
    const userSync = usersProfileSyncPatch(fields);
    if (userSync && collected.delegateUid) {
      const userRef = db.collection("users").doc(collected.delegateUid);
      const userSnap = await userRef.get();
      if (userSnap.exists) {
        batch.update(userRef, asUpdate({
          ...userSync,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));
      }
    }
    await batch.commit();

    if (shouldAlertAdmins(keys)) {
      const changed = keys
        .filter((k) => k === "fullName" || k === "nationalIdFrontUrl" || k === "nationalIdBackUrl")
        .map(fieldArabicLabel)
        .join("، ");
      const who = collected.displayName || collected.delegateUid;
      await notifyPrivileged(db, {
        title: "تعديل بيانات مندوب",
        body: `عدّل المشرف ${caller.name || caller.uid} ${changed} للمندوب ${who}.`,
        type: "delegate_profile_edit",
        senderName: caller.name,
        senderRole: caller.role,
        companyUID,
        organizationUID: collected.organizationUID,
        requestId: requestIdIn || undefined,
        delegateUid: collected.delegateUid,
      });
    }

    return {ok: true, updated: editable.length, fields: keys};
  });

/**
 * submitNationalIdUpdate (company supervisor / company-admin)
 * Creates a pending delegate_requests doc of type update_national_id.
 * Approval is super-admin / technical support only.
 */
export const submitNationalIdUpdate = functions
  .region(REGION)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    const uid = requireAuth(context);
    const db = admin.firestore();
    const caller = await loadCaller(db, uid, context.auth?.token);
    if (!canCallEditDelegateProfile(caller.role)) {
      throw new functions.https.HttpsError("permission-denied", "غير مسموح.");
    }
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const companyUID = typeof payload.companyUID === "string" ? payload.companyUID.trim() : "";
    const newNationalId = normalizeIdDigits(
      typeof payload.newNationalId === "string" ? payload.newNationalId : "",
    );
    const delegateUidIn = typeof payload.delegateUid === "string" ? payload.delegateUid.trim() : "";
    const requestIdIn = typeof payload.requestId === "string" ? payload.requestId.trim() : "";
    if (!companyUID || !newNationalId) {
      throw new functions.https.HttpsError("invalid-argument", "companyUID والرقم القومي الجديد مطلوبان.");
    }
    if (!isValidEgyptianNationalId(newNationalId)) {
      throw new functions.https.HttpsError("invalid-argument", "الرقم القومي يجب أن يكون 14 رقمًا.");
    }
    if (profileEditCompanyScope(caller.role, caller.companyUID, companyUID) !== "ok") {
      throw new functions.https.HttpsError("permission-denied", "غير مسموح.");
    }
    if (!delegateUidIn && !requestIdIn) {
      throw new functions.https.HttpsError("invalid-argument", "delegateUid أو requestId مطلوب.");
    }

    const collected = await collectTargets(db, {
      companyUID,
      delegateUid: delegateUidIn,
      requestId: requestIdIn,
    });
    const currentId = valueOf(collected.targets[0].data as Record<string, unknown>, "nationalId");
    if (currentId && currentId === newNationalId) {
      throw new functions.https.HttpsError("failed-precondition", "الرقم القومي مطابق للقيمة الحالية.");
    }

    const existing = await db.collection("delegate_requests")
      .where("companyUID", "==", companyUID)
      .where("existingDelegateUid", "==", collected.delegateUid)
      .where("requestType", "==", "update_national_id")
      .where("status", "==", "pending")
      .limit(1)
      .get();
    if (!existing.empty) {
      throw new functions.https.HttpsError(
        "already-exists",
        "يوجد طلب تعديل رقم قومي معلّق بالفعل وبانتظار الاعتماد.",
      );
    }

    const dup = await findDuplicatePublic(db, {
      nationalId: newNationalId,
      companyUID,
      excludeDelegateUid: collected.delegateUid,
    });
    throwIfDuplicate(dup, "nationalId");

    const src = collected.targets[0].data;
    const docRef = db.collection("delegate_requests").doc();
    await docRef.set({
      id: docRef.id,
      requestType: "update_national_id",
      actionType: "update_national_id",
      status: "pending",
      paymentStatus: "not_required",
      paymentMethod: "not_required",
      supervisorUid: caller.uid,
      supervisorName: caller.name,
      companyUID,
      companyName: collected.companyName || String(src.companyName || ""),
      organizationUID: collected.organizationUID || String(src.organizationUID || src.organizationId || ""),
      organizationName: String(src.organizationName || ""),
      existingDelegateUid: collected.delegateUid,
      fullName: collected.displayName,
      firstName: String(src.firstName || ""),
      secondName: String(src.secondName || src.middleName || ""),
      thirdName: String(src.thirdName || src.lastName || ""),
      phoneNumber: String(src.phoneNumber || ""),
      nationalId: currentId,
      proposedNationalId: newNationalId,
      profileImageUrl: String(src.profileImageUrl || src.personalPhotoURL || ""),
      nationalIdFrontUrl: String(src.nationalIdFrontUrl || ""),
      nationalIdBackUrl: String(src.nationalIdBackUrl || ""),
      // TAS-331: the Storage paths travel with the URLs.
      ...(typeof src.profileImagePath === "string" && src.profileImagePath ?
        {profileImagePath: src.profileImagePath} : {}),
      ...(typeof src.nationalIdFrontPath === "string" && src.nationalIdFrontPath ?
        {nationalIdFrontPath: src.nationalIdFrontPath} : {}),
      ...(typeof src.nationalIdBackPath === "string" && src.nationalIdBackPath ?
        {nationalIdBackPath: src.nationalIdBackPath} : {}),
      fee: 0,
      remainingMonths: 0,
      createdAt: new Date().toISOString(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await notifyPrivileged(db, {
      title: "طلب تعديل الرقم القومي",
      body: `طلب المشرف ${caller.name || caller.uid} تعديل الرقم القومي للمندوب ${collected.displayName || collected.delegateUid}.`,
      type: "delegate_national_id_request",
      senderName: caller.name,
      senderRole: caller.role,
      companyUID,
      organizationUID: collected.organizationUID,
      requestId: docRef.id,
      delegateUid: collected.delegateUid,
    });

    await db.collection(AUDIT).doc().set({
      ...auditDoc({
        actorUid: caller.uid,
        actorName: caller.name,
        actorRole: caller.role,
        field: "nationalId",
        oldValue: currentId,
        newValue: newNationalId,
        delegateUid: collected.delegateUid,
        delegateName: collected.displayName || collected.delegateUid,
        companyUID,
        companyName: collected.companyName || String(src.companyName || ""),
        organizationUID: collected.organizationUID || String(src.organizationUID || src.organizationId || ""),
        source: "national_id_submission",
        requestId: docRef.id,
      }),
      at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {ok: true, requestId: docRef.id};
  });

/**
 * reviewNationalIdUpdate (super-admin / technical support only)
 * Input: { requestId, approve: boolean, rejectionReason? }
 * On approve, updates nationalId and nationalityID on every chain after a
 * duplicate check, and writes an audit record.
 */
export const reviewNationalIdUpdate = functions
  .region(REGION)
  .runWith({timeoutSeconds: 60, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    const uid = requireAuth(context);
    const db = admin.firestore();
    const caller = await loadCaller(db, uid, context.auth?.token);
    if (!isReviewerRole(caller.role)) {
      throw new functions.https.HttpsError("permission-denied", "الاعتماد متاح للإدارة العليا والدعم الفني فقط.");
    }
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const requestId = typeof payload.requestId === "string" ? payload.requestId.trim() : "";
    const approve = payload.approve === true;
    const rejectionReason = typeof payload.rejectionReason === "string" ? payload.rejectionReason.trim() : "";
    if (!requestId) {
      throw new functions.https.HttpsError("invalid-argument", "requestId مطلوب.");
    }
    const reqRef = db.collection("delegate_requests").doc(requestId);
    const req = await reqRef.get();
    if (!req.exists) {
      throw new functions.https.HttpsError("not-found", "الطلب غير موجود.");
    }
    const request = req.data() || {};
    if (String(request.requestType || request.actionType || "") !== "update_national_id") {
      throw new functions.https.HttpsError("failed-precondition", "هذا الطلب ليس طلب تعديل رقم قومي.");
    }
    if (String(request.status || "") !== "pending") {
      throw new functions.https.HttpsError("failed-precondition", "تمت مراجعة هذا الطلب مسبقاً.");
    }

    const companyUID = String(request.companyUID || "").trim();
    const newId = normalizeIdDigits(String(request.proposedNationalId || ""));
    const delegateUid = String(request.existingDelegateUid || "").trim();
    const supervisorUid = String(request.supervisorUid || "").trim();
    if (reviewerIsSubmitter(uid, supervisorUid)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "لا يجوز لمقدم الطلب اعتماد تعديل الرقم القومي بنفسه.",
      );
    }
    if (!companyUID || !delegateUid) {
      throw new functions.https.HttpsError("failed-precondition", "بيانات الطلب غير مكتملة.");
    }
    if (!isValidEgyptianNationalId(newId)) {
      throw new functions.https.HttpsError("invalid-argument", "الرقم القومي يجب أن يكون 14 رقمًا.");
    }

    let collected: Awaited<ReturnType<typeof collectTargets>> | undefined;
    if (approve) {
      const dup = await findDuplicatePublic(db, {
        nationalId: newId,
        companyUID,
        excludeDelegateUid: delegateUid,
      });
      throwIfDuplicate(dup, "nationalId");
      collected = await collectTargets(db, {companyUID, delegateUid, requestId});
    }

    const result = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(reqRef);
      if (!fresh.exists) {
        throw new functions.https.HttpsError("not-found", "الطلب غير موجود.");
      }
      const freshData = fresh.data() || {};
      if (String(freshData.status || "") !== "pending") {
        throw new functions.https.HttpsError("failed-precondition", "تمت مراجعة هذا الطلب مسبقاً.");
      }
      const organizationUID = String(
        freshData.organizationUID || freshData.organizationId ||
        (collected && collected.organizationUID) || "",
      ).trim();
      const companyName = String(freshData.companyName || (collected && collected.companyName) || "").trim();
      const delegateName = String(freshData.fullName || (collected && collected.displayName) || "").trim();
      const oldId = collected
        ? valueOf(collected.targets[0].data as Record<string, unknown>, "nationalId")
        : String(freshData.nationalId || freshData.nationalityID || "");

      if (!approve) {
        tx.update(reqRef, {
          status: "rejected",
          reviewedBy: uid,
          reviewedByName: caller.name,
          reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
          rejectionReason,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.set(db.collection(AUDIT).doc(), {
          ...auditDoc({
            actorUid: caller.uid,
            actorName: caller.name,
            actorRole: caller.role,
            field: "nationalId",
            oldValue: oldId,
            newValue: newId,
            delegateUid,
            delegateName,
            companyUID,
            companyName,
            organizationUID,
            source: "national_id_rejection",
            requestId,
          }),
          at: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (supervisorUid) {
          tx.set(db.collection("notifications").doc(), {
            ...supervisorReviewAlertDoc({
              supervisorUid,
              approved: false,
              reviewerName: caller.name || caller.uid,
              delegateName,
              companyUID,
              organizationUID,
              requestId,
              targetDelegateUid: delegateUid,
              rejectionReason,
              reviewerRole: caller.role,
            }),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        return {ok: true, status: "rejected" as const, updated: 0};
      }

      // All transactional reads must complete before any write. A second
      // pending or leftover request plus the live delegate would otherwise
      // throw INTERNAL (read-after-write) mid-loop.
      const freshUid = String(freshData.existingDelegateUid || "").trim();
      const freshCompany = String(freshData.companyUID || "").trim();
      const freshProposed = String(freshData.proposedNationalId || "").trim();
      if (freshUid !== delegateUid || freshCompany !== companyUID || freshProposed !== newId) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "بيانات الطلب لم تعد مطابقة لما تم تقديمه.",
        );
      }

      const targets = collected ? collected.targets : [];
      const liveSnaps: FirebaseFirestore.DocumentSnapshot[] = [];
      for (const t of targets) {
        if (t.kind === "request" && t.ref.id === requestId) continue;
        liveSnaps.push(await tx.get(t.ref));
      }
      const matchingDelegates: FirebaseFirestore.DocumentSnapshot[] = [];
      const openRequests: FirebaseFirestore.DocumentSnapshot[] = [];
      for (const live of liveSnaps) {
        const kind = classifyReviewTarget({
          requestDelegateUid: delegateUid,
          requestCompanyUID: companyUID,
          nidRequestId: requestId,
          liveExists: live.exists,
          livePath: live.ref.path,
          liveData: live.exists ? (live.data() || {}) : undefined,
        });
        if (kind === "matching_delegate") {
          matchingDelegates.push(live);
          continue;
        }
        if (kind === "open_request") {
          openRequests.push(live);
          continue;
        }
        if (kind === "delegate_inactive" || kind === "delegate_mismatch") {
          const msg = kind === "delegate_inactive"
            ? "المندوب المستهدف لم يعد نشطاً."
            : "المندوب المستهدف لا يطابق الطلب المقدَّم.";
          throw new functions.https.HttpsError("failed-precondition", msg);
        }
      }
      if (!matchingDelegates.length) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "تعذر التحقق من المندوب المستهدف على الخادم.",
        );
      }
      const userRef = db.collection("users").doc(delegateUid);
      const userSnap = await tx.get(userRef);
      const nidPatch = nationalIdFieldsForApprovedReview(newId);
      if (!nidPatch) {
        throw new functions.https.HttpsError("invalid-argument", "الرقم القومي يجب أن يكون 14 رقمًا.");
      }
      for (const live of [...matchingDelegates, ...openRequests]) {
        tx.update(live.ref, asUpdate({
          ...nidPatch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));
      }
      if (userSnap.exists) {
        tx.update(userRef, asUpdate({
          ...nidPatch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }));
      }
      tx.update(reqRef, {
        status: "approved",
        ...nidPatch,
        reviewedBy: uid,
        reviewedByName: caller.name,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        approvedBy: uid,
        approvedByName: caller.name,
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(db.collection(AUDIT).doc(), {
        ...auditDoc({
          actorUid: caller.uid,
          actorName: caller.name,
          actorRole: caller.role,
          field: "nationalId",
          oldValue: oldId,
          newValue: newId,
          delegateUid,
          delegateName,
          companyUID,
          companyName,
          organizationUID,
          source: "national_id_approval",
          requestId,
        }),
        at: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (supervisorUid) {
        tx.set(db.collection("notifications").doc(), {
          ...supervisorReviewAlertDoc({
            supervisorUid,
            approved: true,
            reviewerName: caller.name || caller.uid,
            delegateName,
            companyUID,
            organizationUID,
            requestId,
            targetDelegateUid: delegateUid,
            reviewerRole: caller.role,
          }),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      return {ok: true, status: "approved" as const, updated: matchingDelegates.length + openRequests.length};
    });
    return result;
  });
