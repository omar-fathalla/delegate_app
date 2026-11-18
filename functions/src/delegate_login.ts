import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  DelegateCandidate,
  buildCustomClaimsForProfiles,
  clearedRateLimit,
  createdAtMillis,
  evaluateCandidates,
  extractNationalId,
  extractPhone,
  idsFromDelegatePath,
  lockStatus,
  nationalIdsMatch,
  normalizePhone,
  phoneQueryVariants,
  rateLimitDocId,
  readString,
  recordFailedAttempt,
  stableDelegateAuthUid,
  validateLoginInput,
} from "./delegate_login_logic";
import {hasDelegateIdentity} from "./delegate_identity";

const RATE_LIMIT_COLLECTION = "delegate_login_rate_limits";

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

async function handleDelegateLogin(data: unknown): Promise<{ token: string; delegateIds: string[] }> {
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
  const claims = buildCustomClaimsForProfiles(profiles, decision.primary, decision.ids);

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
  });

  return {
    token,
    delegateIds: decision.ids,
  };
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

async function findCandidates(
  phone: string,
  nationalId: string,
): Promise<DelegateCandidate[]> {
  const variants = phoneQueryVariants(phone);
  const docs = await queryDelegates(variants);
  const candidates: DelegateCandidate[] = [];
  const seen = new Set<string>();

  for (const doc of docs) {
    if (seen.has(doc.ref.path)) continue;
    seen.add(doc.ref.path);
    const data = doc.data() as Record<string, unknown>;
    const storedPhone = normalizePhone(extractPhone(data));
    if (storedPhone !== phone) continue;

    const pathIds = idsFromDelegatePath(doc.ref.path);
    const companyId = pathIds.companyId || readString(data, ["companyUID", "companyId", "company_id"]);
    const orgId = pathIds.orgId || readString(data, ["organizationUID", "organizationId", "orgId", "organization_id"]);

    candidates.push({
      id: doc.id,
      status: data.status,
      companyId,
      orgId,
      createdAtMillis: createdAtMillis(data.createdAt ?? data.hiredAt ?? data.startDate),
      nationalIdMatches: nationalIdsMatch(extractNationalId(data), nationalId),
      hasIdentity: hasDelegateIdentity(data),
    });
  }

  return candidates;
}

async function queryDelegates(
  variants: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const byPhoneNumber = await queryField("phoneNumber", variants, true);
  if (byPhoneNumber.length > 0) return byPhoneNumber;
  return queryField("phone", variants, false);
}

async function queryField(
  field: string,
  variants: string[],
  required: boolean,
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  try {
    const snap = await admin.firestore()
      .collectionGroup("delegates")
      .where(field, "in", variants)
      .limit(25)
      .get();
    return snap.docs;
  } catch (error) {
    console.error("delegateLoginV2 query failed", field);
    if (required) throw error;
    return [];
  }
}
