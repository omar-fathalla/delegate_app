import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  createdAtMillis,
  lockStatus,
  normalizePhone,
  phoneQueryVariants,
  rateLimitDocId,
  recordFailedAttempt,
} from "./delegate_login_logic";
import {
  callerIp,
  ipWindowNext,
  isStaffRole,
  pickStaffProfile,
  publicStaffProfile,
  PublicStaffProfile,
} from "./staff_phone_lookup_logic";
import {buildPasswordEmail, canSendStaffInvite, DEFAULT_ACTION_PAGE_URL, DEFAULT_LOGO_URL, PasswordEmailVariant} from "./password_email_template";
import {
  PASSWORD_EMAIL_LIMIT_COLLECTION,
  PASSWORD_EMAIL_MAX_PER_TARGET,
  PASSWORD_EMAIL_WINDOW_MS,
  PASSWORD_RESET_MAX_PER_IP,
  PASSWORD_SETUP_MAX_PER_CALLER,
  passwordEmailLimitKey,
  resolveCallerRole,
  staffCreateAllowed,
} from "./staff_password_email_logic";
import {
  buildSetupLink,
  hashSetupToken,
  isWellFormedToken,
  newSetupToken,
  passwordProblem,
  SETUP_TOKEN_COLLECTION,
  SETUP_TOKEN_TTL_MS,
  tokenState,
} from "./password_setup_token_logic";

/**
 * Branded password emails (no password in the email, ever).
 *
 * Config (env vars on the function, all optional):
 *   PASSWORD_ACTION_CONTINUE_URL  continue URL passed in ActionCodeSettings
 *   PASSWORD_ACTION_PAGE_URL      our handler page (default DEFAULT_ACTION_PAGE_URL)
 *   PASSWORD_EMAIL_LOGO_URL       hosted logo PNG (default DEFAULT_LOGO_URL)
 * The handler page itself (the custom action URL) is set in the Firebase
 * console: Authentication → Templates → Customize action URL.
 *
 * Mail is written to the `mail` collection (Trigger Email extension), same as
 * the existing activation email.
 *
 * Links use our own token (password_setup_tokens, sha256 only, 7 days,
 * single use), completed by completeStaffPasswordSetup. Firebase oobCodes
 * expire after ~1 hour, which was too short.
 *
 * Deploy by name only:
 *   firebase deploy --only functions:tashil-mobile-notifications:sendStaffPasswordSetupEmail
 *   firebase deploy --only functions:tashil-mobile-notifications:requestStaffPasswordReset
 *   firebase deploy --only functions:tashil-mobile-notifications:completeStaffPasswordSetup
 */

const RESET_RATE_COLLECTION = "staff_reset_rate_limits";
const GENERIC_RESPONSE = {ok: true};

/**
 * Returns the Auth uid for this email. New accounts use the Firestore doc id
 * as uid, because rules read users/{request.auth.uid}.
 */
async function ensureAuthUser(email: string, displayName: string, docId: string): Promise<string> {
  try {
    return (await admin.auth().getUserByEmail(email)).uid;
  } catch (error) {
    const code = (error as {code?: string}).code;
    if (code !== "auth/user-not-found") throw error;
    // No password is set here; the user picks one from the link.
    const user = await admin.auth().createUser({uid: docId, email, displayName: displayName || undefined, emailVerified: false});
    return user.uid;
  }
}

async function queueEmail(variant: PasswordEmailVariant, email: string, displayName: string, authUid: string): Promise<void> {
  const token = newSetupToken();
  const now = Date.now();
  await admin.firestore().collection(SETUP_TOKEN_COLLECTION).doc(hashSetupToken(token)).set({
    uid: authUid,
    email,
    variant,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(now + SETUP_TOKEN_TTL_MS),
  });
  const link = buildSetupLink(process.env.PASSWORD_ACTION_PAGE_URL || DEFAULT_ACTION_PAGE_URL, token);
  const msg = buildPasswordEmail({
    variant, displayName, link,
    logoUrl: process.env.PASSWORD_EMAIL_LOGO_URL || DEFAULT_LOGO_URL,
  });
  await admin.firestore().collection("mail").add({
    to: [email],
    message: {subject: msg.subject, html: msg.html, text: msg.text},
    meta: {type: `staff_password_${variant}`, createdAt: FieldValue.serverTimestamp()},
  });
}

/**
 * sendStaffPasswordSetupEmail (admin-only)
 * Input: { userId: string, variant?: "new_account" | "forgot_password" }
 * Ensures a Firebase Auth account exists for users/{userId}.email and queues
 * the branded "set your password" email.
 * TAS-317: at most PASSWORD_SETUP_MAX_PER_CALLER per admin per hour and
 * PASSWORD_EMAIL_MAX_PER_TARGET per target email per hour (shared with the
 * public reset). The caller is signed-in staff, so a limit is reported as
 * `resource-exhausted` (reason rate_limited); there is nothing to enumerate.
 */
export const sendStaffPasswordSetupEmail = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth || context.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
    }
    if (!staffCreateAllowed(process.env)) {
      throw new functions.https.HttpsError("failed-precondition", "Staff create is disabled.");
    }
    const callerRole = await callerRoleOf(
      context.auth.uid,
      context.auth.token.email,
      context.auth.token.email_verified === true,
    );
    if (!canSendStaffInvite(callerRole)) {
      throw new functions.https.HttpsError("permission-denied", "Not allowed.");
    }
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const userId = typeof payload.userId === "string" ? payload.userId.trim() : "";
    const variant: PasswordEmailVariant = payload.variant === "forgot_password" ? "forgot_password" : "new_account";
    if (!userId || userId.includes("/")) {
      throw new functions.https.HttpsError("invalid-argument", "userId is required.");
    }
    const callerLimit = await countInWindow(
      passwordEmailLimitKey("caller", context.auth.uid), PASSWORD_SETUP_MAX_PER_CALLER);
    if (!callerLimit.allowed) throw rateLimited(callerLimit.retryAfterSeconds);
    const snap = await admin.firestore().collection("users").doc(userId).get();
    const user = snap.data() as Record<string, unknown> | undefined;
    if (!user || !isStaffRole(user.role)) {
      throw new functions.https.HttpsError("not-found", "Staff user not found.");
    }
    const email = typeof user.email === "string" ? user.email.trim().toLowerCase() : "";
    if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(email) || /\.con$/.test(email)) {
      throw new functions.https.HttpsError("failed-precondition", "Invalid email.", {reason: "invalid_email"});
    }
    const targetLimit = await countInWindow(
      passwordEmailLimitKey("email", email), PASSWORD_EMAIL_MAX_PER_TARGET);
    if (!targetLimit.allowed) throw rateLimited(targetLimit.retryAfterSeconds);
    const displayName = String(user.displayName || user.fullName || user.name || "");
    const authUid = await ensureAuthUser(email, displayName, userId);
    await queueEmail(variant, email, displayName, authUid);
    await snap.ref.set({
      passwordSetupEmailSentAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    console.log("sendStaffPasswordSetupEmail queued", {userId, variant});
    return {ok: true};
  });

async function callerRoleOf(uid: string, email: string | undefined, emailVerified: boolean): Promise<string> {
  const db = admin.firestore();
  return resolveCallerRole(uid, email, emailVerified, {
    getRoleByUid: async (id) => {
      const byId = await db.collection("users").doc(id).get();
      return byId.exists ? String(byId.data()?.role || "") : null;
    },
    getRolesByEmail: async (addr) => {
      const q = await db.collection("users").where("email", "==", addr).limit(5).get();
      return q.docs.map((d) => String(d.data().role || ""));
    },
  });
}

/**
 * requestStaffPasswordReset (public)
 * Input: { phone }. Always returns { ok: true } (no account enumeration).
 * Rate-limited per phone (5 requests / 15 min, then 15 min lock).
 * TAS-317: also PASSWORD_RESET_MAX_PER_IP requests per IP per hour (every
 * request counts) and PASSWORD_EMAIL_MAX_PER_TARGET emails per target address
 * per hour (shared with the admin callable). A limited request still returns
 * { ok: true }, so the caller cannot tell a limit from an unknown phone.
 */
export const requestStaffPasswordReset = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const phoneRaw = payload.phone ?? payload.phoneNumber;
    const phone = normalizePhone(typeof phoneRaw === "string" ? phoneRaw : "");
    if (!/^\d{10,15}$/.test(phone)) {
      throw new functions.https.HttpsError("invalid-argument", "Phone is required.", {reason: "invalid_phone"});
    }
    const key = rateLimitDocId(phone);
    const req = context.rawRequest;
    const ip = callerIp(req?.headers as Record<string, unknown> | undefined, req?.ip);
    try {
      const ipLimit = await countInWindow(passwordEmailLimitKey("ip", ip), PASSWORD_RESET_MAX_PER_IP);
      if (!ipLimit.allowed) {
        console.log("requestStaffPasswordReset: ip limited");
        return GENERIC_RESPONSE;
      }
      if ((await readLock(key)).locked) return GENERIC_RESPONSE;
      await countRequest(key);
      const profile = await findStaff(phone);
      if (!profile) return GENERIC_RESPONSE;
      const targetLimit = await countInWindow(
        passwordEmailLimitKey("email", profile.email), PASSWORD_EMAIL_MAX_PER_TARGET);
      if (!targetLimit.allowed) {
        console.log("requestStaffPasswordReset: target limited", {uid: profile.uid});
        return GENERIC_RESPONSE;
      }
      let authUid: string;
      try {
        authUid = (await admin.auth().getUserByEmail(profile.email)).uid;
      } catch {
        console.log("requestStaffPasswordReset: no auth account", {uid: profile.uid});
        return GENERIC_RESPONSE;
      }
      await queueEmail("forgot_password", profile.email, profile.displayName, authUid);
      console.log("requestStaffPasswordReset queued", {uid: profile.uid});
    } catch {
      console.error("requestStaffPasswordReset failed");
    }
    return GENERIC_RESPONSE;
  });

/**
 * completeStaffPasswordSetup (public)
 * Input: { token, newPassword } sets the password, or { token, check: true }
 * only reports whether the token is usable (does not consume it).
 * Returns { ok: true } or { ok: false, reason: "expired" | "invalid" }.
 * Rate-limited per caller IP (same math as the reset callable).
 */
export const completeStaffPasswordSetup = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    const payload = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const token = payload.token;
    const ip = String(context.rawRequest?.ip || "unknown");
    const key = "setup_" + hashSetupToken(ip).slice(0, 32);
    if ((await readLock(key)).locked) {
      throw new functions.https.HttpsError("resource-exhausted", "Too many attempts.");
    }
    if (!isWellFormedToken(token)) {
      await countRequest(key);
      return {ok: false, reason: "invalid"};
    }
    const ref = admin.firestore().collection(SETUP_TOKEN_COLLECTION).doc(hashSetupToken(token));
    const stateOf = (d: Record<string, unknown> | undefined) => tokenState(d ? {
      usedAtMs: createdAtMillis(d.usedAt) ?? null,
      expiresAtMs: createdAtMillis(d.expiresAt) ?? null,
    } : null, Date.now());

    if (payload.check === true) {
      const st = stateOf((await ref.get()).data());
      if (st === "missing") await countRequest(key);
      return st === "ok" ? {ok: true} : {ok: false, reason: st === "missing" ? "invalid" : "expired"};
    }

    const problem = passwordProblem(payload.newPassword);
    if (problem) throw new functions.https.HttpsError("invalid-argument", "Bad password.", {reason: problem});

    // Claim the token atomically so it can only be used once.
    const claim = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const d = snap.data();
      const st = stateOf(d);
      if (st !== "ok") return {st, uid: ""};
      tx.update(ref, {usedAt: FieldValue.serverTimestamp()});
      return {st, uid: String(d?.uid || "")};
    });
    if (claim.st !== "ok" || !claim.uid) {
      if (claim.st === "missing") await countRequest(key);
      return {ok: false, reason: claim.st === "missing" ? "invalid" : "expired"};
    }
    try {
      await admin.auth().updateUser(claim.uid, {password: payload.newPassword as string});
    } catch (error) {
      // Release the token so the user can retry with a different password.
      await ref.update({usedAt: FieldValue.delete()});
      const code = (error as {code?: string}).code || "";
      if (code === "auth/invalid-password") {
        throw new functions.https.HttpsError("invalid-argument", "Weak password.", {reason: "weak_password"});
      }
      console.error("completeStaffPasswordSetup failed", {code});
      throw new functions.https.HttpsError("internal", "Failed.");
    }
    // TAS-40: a new password ends every older session (stolen refresh
    // tokens included). Best effort: the password is already changed.
    try {
      await admin.auth().revokeRefreshTokens(claim.uid);
    } catch (error) {
      console.error("completeStaffPasswordSetup revoke failed", {code: (error as {code?: string}).code || ""});
    }
    console.log("completeStaffPasswordSetup done", {uid: claim.uid});
    return {ok: true};
  });

async function findStaff(phone: string): Promise<PublicStaffProfile | null> {
  const variants = phoneQueryVariants(phone);
  if (variants.length === 0) return null;
  const users = admin.firestore().collection("users");
  let docs = (await users.where("phoneNumber", "in", variants).limit(10).get()).docs;
  if (docs.length === 0) docs = (await users.where("phone", "in", variants).limit(10).get()).docs;
  const profiles: PublicStaffProfile[] = [];
  for (const doc of docs) {
    const p = publicStaffProfile(doc.id, doc.data() as Record<string, unknown>, phone);
    if (p) profiles.push(p);
  }
  return pickStaffProfile(profiles);
}

async function readLock(key: string): Promise<{locked: boolean}> {
  const snap = await admin.firestore().collection(RESET_RATE_COLLECTION).doc(key).get();
  if (!snap.exists) return {locked: false};
  const d = snap.data() || {};
  return lockStatus({
    failCount: typeof d.failCount === "number" ? d.failCount : 0,
    windowStartMs: createdAtMillis(d.windowStart) ?? 0,
    lockedUntilMs: createdAtMillis(d.lockedUntil) ?? 0,
  }, Date.now());
}

/** Every request counts (success or not), reusing the login rate-limit math. */
async function countRequest(key: string): Promise<void> {
  const ref = admin.firestore().collection(RESET_RATE_COLLECTION).doc(key);
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data() || {};
    const next = recordFailedAttempt(snap.exists ? {
      failCount: typeof d.failCount === "number" ? d.failCount : 0,
      windowStartMs: createdAtMillis(d.windowStart) ?? 0,
      lockedUntilMs: createdAtMillis(d.lockedUntil) ?? 0,
    } : null, Date.now());
    tx.set(ref, {
      failCount: next.failCount,
      windowStart: Timestamp.fromMillis(next.windowStartMs),
      lockedUntil: next.lockedUntilMs > 0 ?
        Timestamp.fromMillis(next.lockedUntilMs) : FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

function rateLimited(retryAfterSeconds: number): functions.https.HttpsError {
  return new functions.https.HttpsError(
    "resource-exhausted",
    "Too many emails. Try again later.",
    {reason: "rate_limited", retryAfterSeconds},
  );
}

/**
 * TAS-317: one fixed-window counter in PASSWORD_EMAIL_LIMIT_COLLECTION
 * (same transaction shape as staffPhoneLookup's IP window). An empty key
 * (no IP known) is not limited here.
 */
async function countInWindow(
  docId: string,
  max: number,
): Promise<{allowed: boolean; retryAfterSeconds: number}> {
  if (!docId) return {allowed: true, retryAfterSeconds: 0};
  const ref = admin.firestore().collection(PASSWORD_EMAIL_LIMIT_COLLECTION).doc(docId);
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data() || {};
    const state = snap.exists ? {
      count: typeof d.count === "number" ? d.count : 0,
      windowStartMs: createdAtMillis(d.windowStart) ?? 0,
    } : null;
    const n = ipWindowNext(state, Date.now(), PASSWORD_EMAIL_WINDOW_MS, max);
    tx.set(ref, {
      count: n.count,
      windowStart: Timestamp.fromMillis(n.windowStartMs),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {allowed: n.allowed, retryAfterSeconds: n.retryAfterSeconds};
  });
}
