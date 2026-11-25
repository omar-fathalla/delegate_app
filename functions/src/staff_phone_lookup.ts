import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  clearedRateLimit,
  createdAtMillis,
  lockStatus,
  normalizePhone,
  phoneQueryVariants,
  rateLimitDocId,
  recordFailedAttempt,
} from "./delegate_login_logic";
import {
  LookupCaller,
  MinimalStaffLookup,
  PublicStaffProfile,
  callerIp,
  ipWindowNext,
  lookupCallerOf,
  pickStaffProfile,
  publicStaffProfile,
  staffLookupResponse,
} from "./staff_phone_lookup_logic";

const RATE_LIMIT_COLLECTION = "staff_login_rate_limits";
// TAS-24: per-IP lookup window (client rules deny this collection).
const IP_LIMIT_COLLECTION = "staff_lookup_ip_limits";

/**
 * staffPhoneLookup
 *
 * Unauthenticated staff login used to list the users collection. Rules no
 * longer allow that read. This callable returns, for one staff phone, the
 * email only (TAS-314) to a signed-out caller, or not-found. After the
 * password sign-in the app calls it again and, as the owner of the account,
 * gets the role and org/company fields. It does not check the password.
 * App Check is not enforced here (out of scope for TAS-314).
 *
 * Deploy this function before the tightened Firestore rules:
 *   firebase deploy --only functions:tashil-mobile-notifications:staffPhoneLookup
 *
 * Do not deploy rules from this change.
 */
export const staffPhoneLookup = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data: unknown, context) => {
    try {
      const req = context.rawRequest;
      await enforceIpWindow(callerIp(req?.headers as Record<string, unknown> | undefined, req?.ip));
      return await handleStaffPhoneLookup(data, lookupCallerOf(context.auth));
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("staffPhoneLookup failed");
      throw new functions.https.HttpsError(
        "internal",
        "Sign-in is temporarily unavailable.",
        { reason: "unavailable" },
      );
    }
  });

async function handleStaffPhoneLookup(
  data: unknown,
  caller: LookupCaller | null,
): Promise<PublicStaffProfile | MinimalStaffLookup> {
  const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
  const phoneRaw = payload.phone ?? payload.phoneNumber;
  const phone = normalizePhone(typeof phoneRaw === "string" ? phoneRaw : "");
  if (!/^\d{10,15}$/.test(phone)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Phone is required.",
      { reason: "invalid_phone" },
    );
  }

  const phoneKey = rateLimitDocId(phone);
  const lock = await readLock(phoneKey);
  if (lock.locked) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Too many attempts. Try again later.",
      { reason: "rate_limited", retryAfterSeconds: lock.retryAfterSeconds },
    );
  }

  const profile = await findStaff(phone);
  if (!profile) {
    await writeFailure(phoneKey);
    throw new functions.https.HttpsError(
      "not-found",
      "Phone or password is incorrect.",
      { reason: "not_found" },
    );
  }

  await clearFailures(phoneKey);
  const body = staffLookupResponse(profile, caller);
  console.log("staffPhoneLookup success", { uid: profile.uid, full: "role" in body });
  return body;
}

async function findStaff(phone: string): Promise<PublicStaffProfile | null> {
  const variants = phoneQueryVariants(phone);
  const byPhoneNumber = await queryUsers("phoneNumber", variants);
  const docs = byPhoneNumber.length > 0 ? byPhoneNumber : await queryUsers("phone", variants);
  const profiles: PublicStaffProfile[] = [];
  for (const doc of docs) {
    const data = doc.data() as Record<string, unknown>;
    const profile = publicStaffProfile(doc.id, data, phone);
    if (profile) profiles.push(profile);
  }
  return pickStaffProfile(profiles);
}

async function queryUsers(
  field: string,
  variants: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  if (variants.length === 0) return [];
  try {
    const snap = await admin.firestore().collection("users").where(field, "in", variants).limit(10).get();
    return snap.docs;
  } catch {
    console.error("staffPhoneLookup query failed", field);
    return [];
  }
}

async function enforceIpWindow(ip: string): Promise<void> {
  if (!ip) return;
  const ref = admin.firestore().collection(IP_LIMIT_COLLECTION).doc(rateLimitDocId(`ip:${ip}`));
  const next = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data() || {};
    const state = snap.exists ? {
      count: typeof d.count === "number" ? d.count : 0,
      windowStartMs: createdAtMillis(d.windowStart) ?? 0,
    } : null;
    const n = ipWindowNext(state, Date.now());
    tx.set(ref, {
      count: n.count,
      windowStart: admin.firestore.Timestamp.fromMillis(n.windowStartMs),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return n;
  });
  if (!next.allowed) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Too many attempts. Try again later.",
      { reason: "rate_limited", retryAfterSeconds: next.retryAfterSeconds },
    );
  }
}

async function readLock(phoneKey: string): Promise<{ locked: boolean; retryAfterSeconds: number }> {
  const snap = await admin.firestore().collection(RATE_LIMIT_COLLECTION).doc(phoneKey).get();
  if (!snap.exists) return { locked: false, retryAfterSeconds: 0 };
  const data = snap.data() || {};
  return lockStatus(
    {
      failCount: typeof data.failCount === "number" ? data.failCount : 0,
      windowStartMs: createdAtMillis(data.windowStart) ?? 0,
      lockedUntilMs: createdAtMillis(data.lockedUntil) ?? 0,
    },
    Date.now(),
  );
}

async function writeFailure(phoneKey: string): Promise<void> {
  const ref = admin.firestore().collection(RATE_LIMIT_COLLECTION).doc(phoneKey);
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const next = recordFailedAttempt(
      snap.exists ? {
        failCount: typeof data.failCount === "number" ? data.failCount : 0,
        windowStartMs: createdAtMillis(data.windowStart) ?? 0,
        lockedUntilMs: createdAtMillis(data.lockedUntil) ?? 0,
      } : null,
      Date.now(),
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
  const cleared = clearedRateLimit(Date.now());
  await admin.firestore().collection(RATE_LIMIT_COLLECTION).doc(phoneKey).set({
    failCount: cleared.failCount,
    windowStart: admin.firestore.Timestamp.fromMillis(cleared.windowStartMs),
    lockedUntil: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}
