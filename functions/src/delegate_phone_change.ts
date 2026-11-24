import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {extractNationalId, extractPhone, phoneQueryVariants} from "./delegate_login_logic";
import {
  Denial,
  OwnDelegateDoc,
  PHONE_CHANGE_COLLECTION,
  PHONE_CHANGE_TTL_MS,
  dayKey,
  decideConfirm,
  decideRequest,
  delegatePatch,
  isDelegateToken,
  isDenial,
  maskPhone,
  nextClaims,
  ownDocs,
  parseRequest,
  toE164,
} from "./delegate_phone_change_logic";

/**
 * TAS-112: a delegate changes its own phone number with an OTP on the new
 * number. The rules keep phoneNumber closed for delegates; these callables
 * write it with the Admin SDK.
 *
 *   firebase deploy --project <id> --only \
 *     functions:tashil-mobile-notifications:requestDelegatePhoneChange,functions:tashil-mobile-notifications:confirmDelegatePhoneChange
 */
const REGION = "us-central1";
const AUDIT = "delegate_profile_audit_logs";

function fail(d: Denial): never {
  throw new functions.https.HttpsError(d.code, d.message, {reason: d.reason});
}

function requireDelegate(context: functions.https.CallableContext): {uid: string; token: Record<string, unknown>} {
  if (!context.auth) {
    fail({code: "unauthenticated", reason: "not_signed_in", message: "Sign in required."});
  }
  const token = context.auth.token as unknown as Record<string, unknown>;
  if (!isDelegateToken(token)) {
    fail({code: "permission-denied", reason: "not_delegate", message: "Delegates only."});
  }
  return {uid: context.auth.uid, token};
}

async function findDelegateDocsByPhones(phones: string[]): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const db = admin.firestore();
  const out = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  const values = Array.from(new Set(phones)).slice(0, 30);
  for (let i = 0; i < values.length; i += 10) {
    const chunk = values.slice(i, i + 10);
    for (const field of ["phoneNumber", "phone"]) {
      const snap = await db.collectionGroup("delegates").where(field, "in", chunk).limit(50).get();
      for (const d of snap.docs) out.set(d.ref.path, d);
    }
  }
  return Array.from(out.values());
}

function toOwn(d: admin.firestore.QueryDocumentSnapshot): OwnDelegateDoc {
  const data = d.data() as Record<string, unknown>;
  return {path: d.ref.path, id: d.id, phone: extractPhone(data), nationalId: extractNationalId(data)};
}

async function phoneTaken(uid: string, ownPaths: Set<string>, newPhone: string): Promise<{
  otherDelegate: boolean;
  staff: boolean;
}> {
  const variants = phoneQueryVariants(newPhone);
  const delegates = await findDelegateDocsByPhones(variants);
  const otherDelegate = delegates.some((d) => !ownPaths.has(d.ref.path));
  const users = await admin.firestore().collection("users")
    .where("phoneNumber", "in", variants.slice(0, 10)).limit(5).get();
  const staff = users.docs.some((d) => d.id !== uid);
  return {otherDelegate, staff};
}

async function loadOwn(uid: string, token: Record<string, unknown>): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const phones = Array.isArray(token.phones) ? token.phones.filter((p) => typeof p === "string") as string[] : [];
  const found = await findDelegateDocsByPhones(phones);
  const keep = new Set(ownDocs(uid, token, found.map(toOwn)).map((d) => d.path));
  return found.filter((d) => keep.has(d.ref.path));
}

export const requestDelegatePhoneChange = functions
  .region(REGION)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data: unknown, context) => {
    const {uid, token} = requireDelegate(context);
    const parsed = parseRequest(data);
    if (isDenial(parsed)) fail(parsed);

    const db = admin.firestore();
    const own = await loadOwn(uid, token);
    const ownPaths = new Set(own.map((d) => d.ref.path));
    const taken = await phoneTaken(uid, ownPaths, parsed.newPhone);

    const now = Date.now();
    const ref = db.collection(PHONE_CHANGE_COLLECTION).doc(uid);
    const prev = (await ref.get()).data() || {};
    const today = dayKey(now);
    const requestsToday = prev.day === today ? Number(prev.requestsToday || 0) : 0;

    const decision = decideRequest({
      parsed,
      own: own.map(toOwn),
      otherDelegateWithPhone: taken.otherDelegate,
      staffWithPhone: taken.staff,
      requestsToday,
    });
    if (isDenial(decision)) {
      console.warn("requestDelegatePhoneChange denied", {uid, reason: decision.reason});
      fail(decision);
    }

    await ref.set({
      uid,
      newPhone: parsed.newPhone,
      status: "pending",
      day: today,
      requestsToday: requestsToday + 1,
      expiresAt: admin.firestore.Timestamp.fromMillis(now + PHONE_CHANGE_TTL_MS),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {ok: true, e164: toE164(parsed.newPhone), expiresInSeconds: PHONE_CHANGE_TTL_MS / 1000};
  });

export const confirmDelegatePhoneChange = functions
  .region(REGION)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (_data: unknown, context) => {
    const {uid, token} = requireDelegate(context);
    const db = admin.firestore();
    const ref = db.collection(PHONE_CHANGE_COLLECTION).doc(uid);
    const pendingSnap = await ref.get();
    const p = pendingSnap.data();
    const pending = p ? {
      newPhone: String(p.newPhone || ""),
      status: String(p.status || ""),
      expiresAtMs: p.expiresAt instanceof admin.firestore.Timestamp ? p.expiresAt.toMillis() : 0,
    } : null;

    const user = await admin.auth().getUser(uid);
    const own = await loadOwn(uid, token);
    const ownPaths = new Set(own.map((d) => d.ref.path));
    const taken = pending?.newPhone ?
      await phoneTaken(uid, ownPaths, pending.newPhone) :
      {otherDelegate: false, staff: false};

    const decision = decideConfirm({
      pending,
      authPhoneE164: user.phoneNumber,
      nowMs: Date.now(),
      otherDelegateWithPhone: taken.otherDelegate,
      staffWithPhone: taken.staff,
    });
    if (isDenial(decision)) {
      console.warn("confirmDelegatePhoneChange denied", {uid, reason: decision.reason});
      fail(decision);
    }
    if (own.length === 0) {
      fail({code: "failed-precondition", reason: "no_profile", message: "Your delegate profile was not found."});
    }

    const newPhone = decision.newPhone;
    const oldPhone = extractPhone(own[0].data() as Record<string, unknown>);
    const batch = db.batch();
    for (const d of own) {
      batch.update(d.ref, {
        ...delegatePatch(d.data() as Record<string, unknown>, newPhone),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        phoneChangedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    const userRef = db.collection("users").doc(uid);
    if ((await userRef.get()).exists) {
      batch.set(userRef, {phoneNumber: newPhone, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    }
    batch.set(ref, {status: "done", doneAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    batch.set(db.collection(AUDIT).doc(), {
      type: "delegate_phone_change_otp",
      delegateUid: uid,
      paths: own.map((d) => d.ref.path),
      oldPhoneMasked: maskPhone(oldPhone),
      newPhoneMasked: maskPhone(newPhone),
      at: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();

    await admin.auth().setCustomUserClaims(uid, nextClaims((user.customClaims || {}) as Record<string, unknown>, newPhone));
    console.log("confirmDelegatePhoneChange done", {uid, copies: own.length});
    return {ok: true, phoneNumber: newPhone, copies: own.length};
  });
