import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {normalizePhone} from "./delegate_login_logic";
import {
  Caller, decideClaim, decideStaffCreate, isValidEmail, nextRate,
  normalizeEmail, setupEmail,
} from "./staff_accounts_logic";

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
  return snap.data() as Caller;
}

async function takeRate(uid: string): Promise<void> {
  const ref = admin.firestore().collection(RATE_COLLECTION).doc(uid);
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
    const [byPhone, byEmail] = await Promise.all([
      db.collection("users").where("phoneNumber", "==", phone).limit(1).get(),
      db.collection("users").where("email", "==", email).limit(1).get(),
    ]);
    if (!byPhone.empty) fail("already-exists", "phone_taken");
    if (!byEmail.empty) fail("already-exists", "email_taken");
    await takeRate(ctx.auth!.uid);

    let user: admin.auth.UserRecord;
    try {
      user = await admin.auth().createUser({email, displayName, emailVerified: false, disabled: false});
    } catch (e) {
      if ((e as {code?: string}).code === "auth/email-already-exists") fail("already-exists", "email_taken");
      throw e;
    }
    const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
    await db.collection("users").doc(user.uid).set({
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
    });
    await queueSetupEmail(email, displayName);
    return {uid: user.uid};
  }));

export const resendStaffSetupLink = functions.region("us-central1").runWith(opts).https.onCall(
  wrap("resendStaffSetupLink", async (data, ctx) => {
    const caller = await loadCaller(ctx);
    const uid = data && typeof data === "object" ? (data as Record<string, unknown>).uid : undefined;
    if (typeof uid !== "string" || !uid) fail("invalid-argument", "invalid_uid");
    const snap = await admin.firestore().collection("users").doc(uid).get();
    if (!snap.exists) fail("not-found", "not_found");
    const t = snap.data() as Record<string, unknown>;
    const d = decideStaffCreate(caller, {
      role: String(t.role ?? ""),
      organizationUID: String(t.organizationUID ?? ""),
      companyUID: String(t.companyUID ?? ""),
    });
    if (!d.ok) fail("permission-denied", d.reason);
    const email = normalizeEmail(t.email);
    if (!isValidEmail(email)) fail("failed-precondition", "no_email");
    await takeRate(ctx.auth!.uid);
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
    const email = normalizeEmail(ctx.auth.token.email);
    const db = admin.firestore();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    return db.runTransaction(async (tx) => {
      const ref = db.collection("invites").doc(inviteId);
      const s = await tx.get(ref);
      const inv = s.data() as Record<string, unknown> | undefined;
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
  }));
