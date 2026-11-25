import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {normalizePhone} from "./delegate_login_logic";
import {
  Caller, decideClaim, decideInviteRegistration, decideStaffCreate, isValidEmail, nextRate,
  normalizeEmail, setupEmail, staffCreateEnabled, isSuperRole,
} from "./staff_accounts_logic";
import {claimBackedCaller, staffClaimsFor} from "./staff_claims";

/**
 * Staff (admin) accounts only. Delegate login and delegate account creation
 * are not touched by this file.
 *
 * Flutter has no App Check yet, so createStaffUser / resendStaffSetupLink do
 * not enforce it (flagged in the plan). claimInvite (Angular) does.
 */
const RATE_COLLECTION = "staff_setup_rate_limits"; // default-deny in rules
const opts = {timeoutSeconds: 30, memory: "256MB" as const};

function fail(code: functions.https.FunctionsErrorCode, reason: string): never {
  throw new functions.https.HttpsError(code, reason, {reason});
}

function wrap<T>(name: string, fn: (d: unknown, c: functions.https.CallableContext) => Promise<T>) {
  return async (data: unknown, ctx: functions.https.CallableContext): Promise<T> => {
    try {
      return await fn(data, ctx);
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error(`${name} failed`, (e as {code?: string})?.code ?? "");
      throw new functions.https.HttpsError("internal", "unavailable", {reason: "unavailable"});
    }
  };
}

async function loadCaller(ctx: functions.https.CallableContext): Promise<Caller> {
  if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
    fail("unauthenticated", "sign_in_required");
  }
  const snap = await admin.firestore().collection("users").doc(ctx.auth.uid).get();
  if (!snap.exists) fail("permission-denied", "caller_not_staff");
  // TAS-23: role and scope from the token claims, not the users doc.
  return claimBackedCaller(snap.data(), ctx.auth.token) as unknown as Caller;
}

function requireEnabled(): void {
  if (!staffCreateEnabled(process.env)) fail("failed-precondition", "staff_create_disabled");
}

async function takeRate(key: string): Promise<void> {
  const ref = admin.firestore().collection(RATE_COLLECTION).doc(key);
  const ok = await admin.firestore().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const next = nextRate(s.data(), Date.now());
    if (!next) return false;
    tx.set(ref, next);
    return true;
  });
  if (!ok) fail("resource-exhausted", "rate_limited");
}

async function queueSetupEmail(email: string, displayName: string): Promise<void> {
  // Firebase reset links expire in about 1 hour (see plan §createStaffUser).
  const link = await admin.auth().generatePasswordResetLink(email);
  await admin.firestore().collection("mail").add({to: [email], message: setupEmail(displayName, link)});
}

export const createStaffUser = functions.region("us-central1").runWith(opts).https.onCall(
  wrap("createStaffUser", async (data, ctx) => {
    const caller = await loadCaller(ctx);
    requireEnabled();
    // Rate first: phone_taken / email_taken must not be an unmetered oracle.
    await takeRate(ctx.auth!.uid);
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const email = normalizeEmail(p.email);
    const phone = normalizePhone(typeof p.phoneNumber === "string" ? p.phoneNumber : "");
    const displayName = typeof p.displayName === "string" ? p.displayName.trim().slice(0, 120) : "";
    const target = {
      role: typeof p.role === "string" ? p.role.trim() : "",
      organizationUID: typeof p.organizationUID === "string" ? p.organizationUID.trim() : "",
      companyUID: typeof p.companyUID === "string" ? p.companyUID.trim() : "",
    };
    if (!isValidEmail(email)) fail("invalid-argument", "invalid_email");
    if (!/^\d{10,15}$/.test(phone)) fail("invalid-argument", "invalid_phone");
    if (!displayName) fail("invalid-argument", "invalid_name");
    const d = decideStaffCreate(caller, target);
    if (!d.ok) fail("permission-denied", d.reason);

    const db = admin.firestore();
    if (target.organizationUID) {
      const org = await db.doc(`organizations/${target.organizationUID}`).get();
      if (!org.exists) fail("invalid-argument", "org_not_found");
    }
    if (target.companyUID) {
      const co = await db.doc(`organizations/${target.organizationUID}/companies/${target.companyUID}`).get();
      if (!co.exists) fail("invalid-argument", "company_not_found");
    }
    const taken = async (get: (q: FirebaseFirestore.Query) => Promise<FirebaseFirestore.QuerySnapshot>) => {
      const [byPhone, byEmail] = await Promise.all([
        get(db.collection("users").where("phoneNumber", "==", phone).limit(1)),
        get(db.collection("users").where("email", "==", email).limit(1)),
      ]);
      if (!byPhone.empty) fail("already-exists", "phone_taken");
      if (!byEmail.empty) fail("already-exists", "email_taken");
    };
    await taken((q) => q.get());

    let user: admin.auth.UserRecord;
    try {
      user = await admin.auth().createUser({email, displayName, emailVerified: false, disabled: false});
    } catch (e) {
      if ((e as {code?: string}).code === "auth/email-already-exists") fail("already-exists", "email_taken");
      throw e;
    }
    const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
    const userDoc = {
      uid: user.uid,
      email,
      phoneNumber: phone,
      displayName,
      role: target.role,
      organizationUID: target.organizationUID,
      companyUID: target.companyUID,
      ...(str(p.companyName) ? {companyName: str(p.companyName).slice(0, 200)} : {}),
      ...(str(p.jobTitle) ? {jobTitle: str(p.jobTitle).slice(0, 120)} : {}),
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: ctx.auth!.uid,
    };
    try {
      // TAS-23: the staff callables read the role and scope from claims, so the
      // new account gets them now (Admin SDK only), before its profile exists.
      const claims = staffClaimsFor(target.role, target.organizationUID, target.companyUID);
      if (claims) await admin.auth().setCustomUserClaims(user.uid, {...claims});
      // Uniqueness re-checked inside the transaction; create() never overwrites.
      await db.runTransaction(async (tx) => {
        await taken((q) => tx.get(q));
        tx.create(db.collection("users").doc(user.uid), userDoc);
      });
    } catch (e) {
      // No orphaned Auth user when the profile write fails.
      await admin.auth().deleteUser(user.uid).catch(() => undefined);
      throw e;
    }
    await queueSetupEmail(email, displayName);
    return {uid: user.uid};
  }));

export const resendStaffSetupLink = functions.region("us-central1").runWith(opts).https.onCall(
  wrap("resendStaffSetupLink", async (data, ctx) => {
    const caller = await loadCaller(ctx);
    requireEnabled();
    await takeRate(ctx.auth!.uid);
    const uid = data && typeof data === "object" ? (data as Record<string, unknown>).uid : undefined;
    if (typeof uid !== "string" || !uid) fail("invalid-argument", "invalid_uid");
    const snap = await admin.firestore().collection("users").doc(uid).get();
    // Only a global caller learns that a uid does not exist; everyone else
    // gets the same out_of_scope answer for missing and foreign accounts.
    if (!snap.exists) {
      if (isSuperRole(caller.role) && caller.isActive !== false) fail("not-found", "not_found");
      fail("permission-denied", "out_of_scope");
    }
    const t = snap.data() as Record<string, unknown>;
    const d = decideStaffCreate(caller, {
      role: String(t.role ?? ""),
      organizationUID: String(t.organizationUID ?? ""),
      companyUID: String(t.companyUID ?? ""),
    });
    if (!d.ok) fail("permission-denied", d.reason);
    const email = normalizeEmail(t.email);
    if (!isValidEmail(email)) fail("failed-precondition", "no_email");
    await queueSetupEmail(email, String(t.displayName ?? ""));
    return {queued: true};
  }));

export const claimInvite = functions.region("us-central1")
  .runWith({...opts, enforceAppCheck: true})
  .https.onCall(wrap("claimInvite", async (data, ctx) => {
    if (!ctx.auth) fail("unauthenticated", "sign_in_required");
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const inviteId = typeof p.inviteId === "string" ? p.inviteId : "";
    const displayName = typeof p.displayName === "string" ? p.displayName.trim().slice(0, 120) : "";
    if (!inviteId || !displayName) fail("invalid-argument", "invalid_input");
    const uid = ctx.auth.uid;
    await takeRate(`claim_${uid}`);
    const email = normalizeEmail(ctx.auth.token.email);
    const db = admin.firestore();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("invites").doc(inviteId);
      const s = await tx.get(ref);
      const inv = s.data() as Record<string, unknown> | undefined;
      // Safe retry: the same caller re-claiming an invite it already claimed
      // gets the original result and nothing is written again.
      if (inv && inv.status === "claimed" && inv.claimedByUid === uid) {
        const co0 = typeof inv.companyId === "string" ? inv.companyId : "";
        return {
          inviteId, status: "claimed", roleToAssign: inv.roleToAssign,
          organizationId: String(inv.organizationId ?? ""), companyId: co0 || null,
          isFirstAdmin: inv.isFirstAdmin === true,
        };
      }
      const exp = inv?.expiresAt as {toMillis?: () => number} | undefined;
      const d = decideClaim(inv, {email, emailVerified: ctx.auth!.token.email_verified === true},
        Date.now(), typeof exp?.toMillis === "function" ? exp.toMillis() : null);
      if (!d.ok) fail("failed-precondition", d.reason);
      const i = inv as Record<string, unknown>;
      const org = String(i.organizationId);
      const co = typeof i.companyId === "string" ? i.companyId : "";
      const isOrg = i.roleToAssign === "org-admin";
      const scopeRef = isOrg ? db.doc(`organizations/${org}`) : db.doc(`organizations/${org}/companies/${co}`);
      const scope = await tx.get(scopeRef);
      if (!scope.exists) fail("failed-precondition", "scope_not_found");
      const existing = await tx.get(db.collection("users").doc(uid));
      if (existing.exists && existing.data()?.role) fail("failed-precondition", "account_has_role");
      tx.set(scopeRef.collection("members").doc(uid), {
        role: i.roleToAssign, status: "active", displayName, createdAt: ts, invitedBy: i.invitedByUid ?? null,
      });
      tx.set(db.collection("users").doc(uid), {
        uid, email, displayName,
        phoneNumber: typeof i.phoneNumber === "string" ? i.phoneNumber : null,
        role: isOrg ? "organization-admin" : "company-admin",
        emailVerified: true,
        organizationUID: org,
        organizationName: i.organizationName ?? "",
        ...(isOrg ? {} : {companyUID: co, companyName: i.companyName ?? ""}),
        status: "Approved", createdAt: ts, updatedAt: ts,
      });
      tx.update(scopeRef, {admins: admin.firestore.FieldValue.increment(1), updatedAt: ts});
      tx.update(ref, {status: "claimed", claimedAt: ts, claimedByUid: uid, claimedByEmail: email, updatedAt: ts});
      return {
        inviteId, status: "claimed", roleToAssign: i.roleToAssign, organizationId: org,
        companyId: co || null, isFirstAdmin: i.isFirstAdmin === true,
      };
    });
    // TAS-68: the claim proved the email; record it, and give the admin the
    // role claims the approval callables read (TAS-23). Best effort: the
    // Firestore claim above is the source of truth.
    try {
      const user = await admin.auth().getUser(uid);
      const isOrgAdmin = result.roleToAssign === "org-admin";
      await admin.auth().setCustomUserClaims(uid, {
        ...(user.customClaims || {}),
        role: isOrgAdmin ? "organization-admin" : "company-admin",
        orgId: result.organizationId,
        ...(isOrgAdmin || !result.companyId ? {} : {companyId: result.companyId}),
      });
      if (!user.emailVerified) await admin.auth().updateUser(uid, {emailVerified: true});
    } catch (error) {
      console.warn("claimInvite auth update skipped", {uid});
    }
    return result;
  }));

/**
 * TAS-17: the invite page (finish-signup) used to create the admin's Auth
 * account in the browser (createUserWithEmailAndPassword), which keeps
 * Identity Platform sign-up open for anyone with the API key. This callable
 * creates it with the Admin SDK instead, only for a pending, unexpired
 * invite and only for the invite's own email. The browser then signs in
 * with the password and calls claimInvite as before. No sign-in needed;
 * App Check is enforced and each invite id is rate limited.
 * Returns {created: true} for a new account, {created: false} when the
 * email already has an account (the page then signs in with it).
 */
export const registerInvitedAdmin = functions.region("us-central1")
  .runWith({...opts, enforceAppCheck: true})
  .https.onCall(wrap("registerInvitedAdmin", async (data) => {
    const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
    const inviteId = typeof p.inviteId === "string" ? p.inviteId.trim() : "";
    const displayName = typeof p.displayName === "string" ? p.displayName.trim().slice(0, 120) : "";
    if (!inviteId || inviteId.length > 200 || inviteId.includes("/")) fail("invalid-argument", "invalid_input");
    const snap = await admin.firestore().collection("invites").doc(inviteId).get();
    if (!snap.exists) fail("failed-precondition", "invite_not_found");
    // Rate limit only real invites, so random ids cost no writes.
    await takeRate(`register_${inviteId}`);
    const inv = snap.data() as Record<string, unknown>;
    const exp = inv?.expiresAt as {toMillis?: () => number} | undefined;
    const d = decideInviteRegistration(inv, p.password, Date.now(),
      typeof exp?.toMillis === "function" ? exp.toMillis() : null);
    if (!d.ok) fail(d.reason === "weak_password" ? "invalid-argument" : "failed-precondition", d.reason);
    const email = normalizeEmail((inv as Record<string, unknown>).email);
    try {
      await admin.auth().createUser({
        email, password: p.password as string,
        ...(displayName ? {displayName} : {}),
      });
      return {created: true};
    } catch (e) {
      const code = (e as {code?: string})?.code ?? "";
      if (code === "auth/email-already-exists") return {created: false};
      if (code === "auth/invalid-password") fail("invalid-argument", "weak_password");
      throw e;
    }
  }));
