import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  DelegateCandidate,
  OTP_ENFORCEMENT_DOC,
  applyOtpEnforcementClaims,
  buildCustomClaimsForProfiles,
  clearedRateLimit,
  createdAtMillis,
  decideDeviceBinding,
  evaluateCandidates,
  extractNationalId,
  extractPhone,
  idsFromDelegatePath,
  lockStatus,
  nationalIdsMatch,
  normalizeNationalId,
  normalizePhone,
  DELEGATE_LOGIN_LOOKUP_PAGE_SIZE,
  optionalDeviceLabel,
  parseOtpEnforcementEnabled,
  phoneQueryVariants,
  rateLimitDocId,
  readString,
  recordFailedAttempt,
  stableDelegateAuthUid,
  validateDeviceId,
  validateLoginInput,
  isStaffAccountRecord,
} from "./delegate_login_logic";
import {hasDelegateIdentity, isDeletedDelegateStatus} from "./delegate_identity";

const RATE_LIMIT_COLLECTION = "delegate_login_rate_limits";
const DEVICE_BINDINGS = "deviceBindings";
const UNBIND_REQUESTS = "device_unbind_requests";

/**
 * delegateLoginV2
 *
 * Verifies a delegate's mobile number and national ID together and returns a
 * Firebase custom token. This is a new function name on purpose: the currently
 * released app does not call it, and the existing notification triggers in this
 * codebase are left unchanged.
 *
 * Deploy only this function, after review:
 *   firebase deploy --only functions:tashil-mobile-notifications:delegateLoginV2
 *
 * Do not deploy Firestore rules in the same change. See
 * functions/scripts/README-delegate-auth-backfill.md for the optional backfill
 * that is NOT required before the first login.
 *
 * deviceId is required. The released app does not call this function, so
 * publishing it does not change those installs. A build that calls it without
 * deviceId is rejected with missing_device. Delegates who already have
 * boundDeviceId and no deviceBindings doc keep that device on the first V2
 * login. Delegates with neither are bound to the device that calls. After
 * the rules in this repo are published, clients can no longer write
 * boundDeviceId; an old build that still tries will fail that write.
 */
export const delegateLoginV2 = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data: unknown) => {
    try {
      return await handleDelegateLogin(data);
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("delegateLoginV2 failed");
      throw new functions.https.HttpsError(
        "internal",
        "Sign-in is temporarily unavailable.",
        { reason: "unavailable" },
      );
    }
  });

async function handleDelegateLogin(data: unknown): Promise<{ token: string; delegateIds: string[]; otpRequired: boolean }> {
  const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
  const phoneRaw = payload.phone ?? payload.phoneNumber;
  const nationalIdRaw = payload.nationalId ?? payload.nationalityID ?? payload.nationalityId;
  const validated = validateLoginInput(phoneRaw, nationalIdRaw);
  if (!validated.ok) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Phone and national ID are required.",
      { reason: validated.reason },
    );
  }
  const device = validateDeviceId(payload.deviceId ?? payload.device_id);
  if (!device.ok) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A device id is required.",
      { reason: device.reason },
    );
  }
  const deviceModel = optionalDeviceLabel(payload.deviceModel ?? payload.device_model);

  const phoneKey = rateLimitDocId(validated.phone);
  const lock = await readLock(phoneKey);
  if (lock.locked) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Too many attempts. Try again later.",
      { reason: "rate_limited", retryAfterSeconds: lock.retryAfterSeconds },
    );
  }

  const candidates = await findCandidates(validated.phone, validated.nationalId);
  const decision = evaluateCandidates(candidates);

  if (decision.outcome === "not_found") {
    await writeFailure(phoneKey);
    throw new functions.https.HttpsError(
      "not-found",
      "Phone or national ID is incorrect.",
      { reason: "not_found" },
    );
  }
  if (decision.outcome === "bad_credentials") {
    await writeFailure(phoneKey);
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Phone or national ID is incorrect.",
      { reason: "bad_credentials" },
    );
  }
  if (decision.outcome === "profile_missing") {
    await writeFailure(phoneKey);
    throw new functions.https.HttpsError(
      "not-found",
      "This delegate profile no longer exists.",
      { reason: "profile_missing" },
    );
  }
  if (decision.outcome === "deleted") {
    await writeFailure(phoneKey);
    throw new functions.https.HttpsError(
      "permission-denied",
      "This delegate account was deleted.",
      { reason: "account_deleted" },
    );
  }
  if (decision.outcome === "inactive") {
    await writeFailure(phoneKey);
    throw new functions.https.HttpsError(
      "permission-denied",
      "This delegate account cannot sign in.",
      { reason: "account_inactive" },
    );
  }

  const profiles = candidates.filter(
    (candidate) => decision.ids.indexOf(candidate.id) !== -1,
  );
  const uid = stableDelegateAuthUid(decision.primary.id);
  const deviceDecision = await enforceDeviceBinding({
    uid,
    primary: decision.primary,
    profiles,
    deviceId: device.deviceId,
    deviceModel,
    phone: validated.phone,
  });
  if (deviceDecision.action === "profile_missing") {
    // The primary link doc was deleted (or is a ghost) between lookup and bind.
    throw new functions.https.HttpsError(
      "not-found",
      "This delegate profile no longer exists.",
      { reason: "profile_missing" },
    );
  }
  if (deviceDecision.action === "mismatch") {
    await clearFailures(phoneKey);
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This account is bound to another device.",
      { reason: "device_mismatch", requestStatus: "pending" },
    );
  }

  const baseClaims = buildCustomClaimsForProfiles(
    profiles,
    decision.primary,
    decision.ids,
    deviceDecision.deviceId,
  );
  const otpEnforcement = await readOtpEnforcementEnabled();
  const claims = applyOtpEnforcementClaims(baseClaims, otpEnforcement);

  // TAS-22 (hotfix live on prod since 2026-11-20): never mint a token for,
  // or overwrite the claims of, a staff account whose uid was planted as a
  // delegate doc id.
  if (await isStaffAccount(uid)) {
    await writeFailure(phoneKey);
    console.error("delegateLoginV2 refused: delegate id collides with a staff account", decision.primary.id);
    throw new functions.https.HttpsError(
      "permission-denied",
      "This delegate account cannot sign in.",
      { reason: "account_inactive" },
    );
  }

  try {
    await admin.auth().setCustomUserClaims(uid, claims);
  } catch (error) {
    console.error("delegateLoginV2 claims update failed", decision.primary.id);
  }

  const token = await admin.auth().createCustomToken(uid, claims);
  await clearFailures(phoneKey);
  console.log("delegateLoginV2 success", {
    delegateId: decision.primary.id,
    profiles: decision.ids.length,
    otpRequired: otpEnforcement,
  });

  return {
    token,
    delegateIds: decision.ids,
    otpRequired: otpEnforcement,
  };
}

/** Server switch. Missing doc / read error => false so login stays open. */
async function readOtpEnforcementEnabled(): Promise<boolean> {
  try {
    const snap = await admin.firestore().doc(OTP_ENFORCEMENT_DOC).get();
    return parseOtpEnforcementEnabled(snap.exists ? snap.data() : null);
  } catch (error) {
    console.error("delegateLoginV2 otp enforcement read failed");
    return false;
  }
}

async function isStaffAccount(uid: string): Promise<boolean> {
  let record: admin.auth.UserRecord | null = null;
  try {
    record = await admin.auth().getUser(uid);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code !== "auth/user-not-found") throw error;
  }
  const userDoc = await admin.firestore().collection("users").doc(uid).get();
  return isStaffAccountRecord({
    claimRole: record?.customClaims?.role,
    hasPassword: !!record?.providerData.some((p) => p.providerId === "password"),
    userDocRole: userDoc.exists ? userDoc.get("role") : "",
  });
}

async function readLock(phoneKey: string): Promise<{ locked: boolean; retryAfterSeconds: number }> {
  const snap = await admin.firestore().collection(RATE_LIMIT_COLLECTION).doc(phoneKey).get();
  if (!snap.exists) return { locked: false, retryAfterSeconds: 0 };
  const data = snap.data() || {};
  return lockStatus(
    {
      failCount: typeof data.failCount === "number" ? data.failCount : 0,
      windowStartMs: millisOf(data.windowStart),
      lockedUntilMs: millisOf(data.lockedUntil),
    },
    Date.now(),
  );
}

async function writeFailure(phoneKey: string): Promise<void> {
  const ref = admin.firestore().collection(RATE_LIMIT_COLLECTION).doc(phoneKey);
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const now = Date.now();
    const next = recordFailedAttempt(
      snap.exists ? {
        failCount: typeof data.failCount === "number" ? data.failCount : 0,
        windowStartMs: millisOf(data.windowStart),
        lockedUntilMs: millisOf(data.lockedUntil),
      } : null,
      now,
    );
    const payload: Record<string, unknown> = {
      failCount: next.failCount,
      windowStart: admin.firestore.Timestamp.fromMillis(next.windowStartMs),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (next.lockedUntilMs > 0) {
      payload.lockedUntil = admin.firestore.Timestamp.fromMillis(next.lockedUntilMs);
    } else {
      payload.lockedUntil = admin.firestore.FieldValue.delete();
    }
    tx.set(ref, payload, { merge: true });
  });
}

async function clearFailures(phoneKey: string): Promise<void> {
  const now = Date.now();
  const cleared = clearedRateLimit(now);
  await admin.firestore().collection(RATE_LIMIT_COLLECTION).doc(phoneKey).set({
    failCount: cleared.failCount,
    windowStart: admin.firestore.Timestamp.fromMillis(cleared.windowStartMs),
    lockedUntil: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

function millisOf(value: unknown): number {
  return createdAtMillis(value) ?? 0;
}

async function enforceDeviceBinding(input: {
  uid: string;
  primary: DelegateCandidate;
  profiles: DelegateCandidate[];
  deviceId: string;
  deviceModel: string;
  phone: string;
}): Promise<
  { action: "bind" | "allow"; deviceId: string } | { action: "mismatch" } | { action: "profile_missing" }
> {
  const db = admin.firestore();
  const bindingRef = db.collection(DEVICE_BINDINGS).doc(input.uid);
  const requests = await loadOpenUnbindRequests(input.profiles.map((profile) => profile.id));
  const approved = requests.find((request) => request.status === "approved") || null;
  const pending = requests.find((request) => request.status === "pending") || null;

  const primaryRef = input.primary.path ? db.doc(input.primary.path) : null;
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bindingRef);
    // Re-read the primary link doc inside the transaction: a deleted or ghost
    // profile must not get a binding or a token.
    if (primaryRef) {
      const primarySnap = await tx.get(primaryRef);
      const primaryData = primarySnap.exists ? primarySnap.data() : null;
      if (!primaryData || !hasDelegateIdentity(primaryData) ||
          isDeletedDelegateStatus(primaryData.status)) {
        return { action: "profile_missing" as const };
      }
    }
    const serverId = snap.exists ? readString(snap.data() || {}, ["deviceId"]) : "";
    const legacyId = input.primary.boundDeviceId || "";
    const decision = decideDeviceBinding({
      storedDeviceId: serverId || legacyId,
      requestedDeviceId: input.deviceId,
      approvedRequestId: approved ? approved.id : null,
      pendingRequestId: pending ? pending.id : null,
    });
    if (decision.action === "mismatch") return decision;

    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload: Record<string, unknown> = {
      deviceId: decision.deviceId,
      delegateId: input.primary.id,
      orgId: input.primary.orgId,
      companyId: input.primary.companyId,
      updatedAt: now,
    };
    if (decision.action === "bind" || !snap.exists) {
      payload.boundAt = now;
    }
    if (input.deviceModel) payload.deviceModel = input.deviceModel;
    tx.set(bindingRef, payload, { merge: true });
    if (decision.action === "bind" && decision.consumeRequestId) {
      tx.update(db.collection(UNBIND_REQUESTS).doc(decision.consumeRequestId), {
        status: "completed",
        consumedAt: now,
        consumedDeviceId: decision.deviceId,
      });
    }
    return decision;
  });

  if (outcome.action === "profile_missing") return { action: "profile_missing" };
  if (outcome.action === "mismatch") {
    await upsertPendingUnbindRequest({
      existingId: outcome.pendingRequestId,
      primary: input.primary,
      phone: input.phone,
      requestedDeviceId: input.deviceId,
      requestedDeviceModel: input.deviceModel,
      boundDeviceId: outcome.boundDeviceId,
    });
    return { action: "mismatch" };
  }

  await mirrorBoundDevice(
    input.profiles,
    outcome.deviceId,
    input.deviceModel,
    outcome.action === "bind",
  );
  return { action: outcome.action, deviceId: outcome.deviceId };
}

async function loadOpenUnbindRequests(
  delegateIds: string[],
): Promise<Array<{ id: string; status: string }>> {
  const ids = Array.from(new Set(delegateIds.filter((id) => id))).slice(0, 10);
  if (ids.length === 0) return [];
  try {
    const snap = await admin.firestore()
      .collection(UNBIND_REQUESTS)
      .where("delegateUid", "in", ids)
      .limit(20)
      .get();
    return snap.docs
      .map((doc) => ({
        id: doc.id,
        status: readString(doc.data(), ["status"]),
      }))
      .filter((request) => request.status === "pending" || request.status === "approved");
  } catch {
    console.error("delegateLoginV2 unbind lookup failed");
    return [];
  }
}

async function upsertPendingUnbindRequest(input: {
  existingId: string | null;
  primary: DelegateCandidate;
  phone: string;
  requestedDeviceId: string;
  requestedDeviceModel: string;
  boundDeviceId: string;
}): Promise<void> {
  const db = admin.firestore();
  const ref = input.existingId
    ? db.collection(UNBIND_REQUESTS).doc(input.existingId)
    : db.collection(UNBIND_REQUESTS).doc();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const payload: Record<string, unknown> = {
    id: ref.id,
    delegateUid: input.primary.id,
    delegateName: input.primary.fullName || "",
    delegatePhone: input.phone,
    organizationUID: input.primary.orgId,
    companyUID: input.primary.companyId,
    boundDeviceId: input.boundDeviceId,
    boundDeviceModel: input.primary.boundDeviceModel || "",
    requestedDeviceId: input.requestedDeviceId,
    requestedDeviceModel: input.requestedDeviceModel,
    status: "pending",
    reason: "طلب تغيير الجهاز من تسجيل الدخول",
    updatedAt: now,
  };
  if (!input.existingId) payload.createdAt = now;
  await ref.set(payload, { merge: true });
}

async function mirrorBoundDevice(
  profiles: DelegateCandidate[],
  deviceId: string,
  deviceModel: string,
  firstBind: boolean,
): Promise<void> {
  const now = admin.firestore.FieldValue.serverTimestamp();
  await Promise.all(profiles.map(async (profile) => {
    if (!profile.path) return;
    const update: Record<string, unknown> = {
      boundDeviceId: deviceId,
      deviceLastSeenAt: now,
      isDeviceLocked: true,
    };
    if (firstBind) update.deviceBoundAt = now;
    if (deviceModel) update.boundDeviceModel = deviceModel;
    try {
      // update(), not set(merge): a link doc deleted meanwhile must stay
      // deleted. set(merge) would re-create it as a nameless ghost.
      await admin.firestore().doc(profile.path).update(update);
    } catch (error) {
      const code = (error as { code?: unknown })?.code;
      if (code === 5 || code === "not-found") {
        console.warn("delegateLoginV2 device mirror skipped: link doc missing", profile.id);
      } else {
        console.error("delegateLoginV2 device mirror failed", profile.id);
      }
    }
  }));
}

async function findCandidates(
  phone: string,
  nationalId: string,
): Promise<DelegateCandidate[]> {
  const variants = phoneQueryVariants(phone);
  const docs = await queryDelegates(variants, nationalId);
  const candidates: DelegateCandidate[] = [];
  const seen = new Set<string>();

  for (const doc of docs) {
    if (seen.has(doc.ref.path)) continue;
    seen.add(doc.ref.path);
    const data = doc.data() as Record<string, unknown>;
    const storedPhone = normalizePhone(extractPhone(data));
    const nationalIdMatches = nationalIdsMatch(extractNationalId(data), nationalId);
    if (!nationalIdMatches && storedPhone !== phone) continue;

    const pathIds = idsFromDelegatePath(doc.ref.path);
    const companyId = pathIds.companyId || readString(data, ["companyUID", "companyId", "company_id"]);
    const orgId = pathIds.orgId || readString(data, ["organizationUID", "organizationId", "orgId", "organization_id"]);

    candidates.push({
      id: doc.id,
      status: data.status,
      statusReason: readString(data, ["statusReason", "status_reason"]),
      holds: data.holds,
      companyId,
      orgId,
      phone: storedPhone,
      path: doc.ref.path,
      boundDeviceId: readString(data, ["boundDeviceId"]),
      boundDeviceModel: readString(data, ["boundDeviceModel"]),
      fullName: readString(data, ["fullName", "name"]),
      hasIdentity: hasDelegateIdentity(data),
      createdAtMillis: createdAtMillis(data.createdAt ?? data.hiredAt ?? data.startDate),
      nationalIdMatches,
      phoneMatchesLogin: storedPhone === phone,
    });
  }

  return candidates;
}

async function queryDelegates(
  variants: string[],
  nationalId: string,
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const normalizedNationalId = normalizeNationalId(nationalId);
  const merged = await mergeDelegateLookupDocs([
    ...(await paginatedDelegatesPhoneField("phoneNumber", variants)),
    ...(await paginatedDelegatesPhoneField("phone", variants)),
    ...(await paginatedDelegatesEqual("nationalityID", normalizedNationalId)),
    ...(await paginatedDelegatesEqual("nationalId", normalizedNationalId)),
    ...(await paginatedDelegatesEqual("nationalID", normalizedNationalId)),
    ...(await paginatedDelegatesEqual("nationalityId", normalizedNationalId)),
    ...(await paginatedDelegatesEqual("national_id", normalizedNationalId)),
    ...(await paginatedDelegatesEqual("idNumber", normalizedNationalId)),
  ]);
  return merged;
}

async function mergeDelegateLookupDocs(
  docs: admin.firestore.QueryDocumentSnapshot[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const byPath = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const doc of docs) {
    byPath.set(doc.ref.path, doc);
  }
  return Array.from(byPath.values());
}

async function paginatedDelegatesPhoneField(
  field: string,
  values: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const out: admin.firestore.QueryDocumentSnapshot[] = [];
  for (const value of new Set(values.filter((entry) => entry))) {
    out.push(...(await paginatedDelegatesEqual(field, value)));
  }
  return out;
}

async function paginatedDelegatesEqual(
  field: string,
  value: string,
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  if (!value) return [];
  const out: admin.firestore.QueryDocumentSnapshot[] = [];
  const db = admin.firestore();
  try {
    let last: admin.firestore.QueryDocumentSnapshot | undefined;
    for (;;) {
      let query: admin.firestore.Query = db.collectionGroup("delegates")
        .where(field, "==", value)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(DELEGATE_LOGIN_LOOKUP_PAGE_SIZE);
      if (last) query = query.startAfter(last);
      const snap = await query.get();
      out.push(...snap.docs);
      if (snap.empty || snap.size < DELEGATE_LOGIN_LOOKUP_PAGE_SIZE) break;
      last = snap.docs[snap.docs.length - 1];
    }
  } catch (error) {
    console.error("delegateLoginV2 query failed", field);
  }
  return out;
}
