import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {
  BATCH_SIZE,
  Candidate,
  CallerScope,
  Denial,
  MAX_RECIPIENTS,
  NotificationFields,
  NotifyTarget,
  ROLE_LABELS_AR,
  authorizeTarget,
  callerScopeFrom,
  candidateFrom,
  chunk,
  filterRecipients,
  notificationDoc,
  parseRequest,
  phoneVariants,
  recipientOrgCompany,
  senderRoleName,
  targetRoleSpellings,
} from "./send_staff_notification_logic";

type Db = admin.firestore.Firestore;
type Snap = admin.firestore.QueryDocumentSnapshot | admin.firestore.DocumentSnapshot;

function fail(d: Denial): never {
  throw new functions.https.HttpsError(d.code, d.message, {reason: d.reason});
}

function tooMany(): never {
  throw new functions.https.HttpsError(
    "failed-precondition",
    "Too many recipients for one send.",
    {reason: "too_many_recipients", max: MAX_RECIPIENTS},
  );
}

/**
 * sendStaffNotification (TAS-216)
 *
 * Staff send screen. Resolves recipients and writes notifications/ +
 * sent_notifications/ with the Admin SDK, inside the caller's scope read
 * from users/{uid}. Delegates are rejected.
 *
 * Deploy before (or with) the TAS-51 rules:
 *   firebase deploy --project <id> --only functions:tashil-mobile-notifications:sendStaffNotification
 */
export const sendStaffNotification = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 300, memory: "1GB"})
  .https.onCall(async (data: unknown, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in required.", {reason: "unauthenticated"});
    }
    try {
      return await handle(admin.firestore(), context.auth.uid, context.auth.token?.role, data);
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("sendStaffNotification failed", (error as Error)?.message);
      throw new functions.https.HttpsError("internal", "Send failed.", {reason: "internal"});
    }
  });

async function handle(db: Db, uid: string, tokenRole: unknown, data: unknown) {
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.exists ? (userSnap.data() || {}) : null;
  const scope = callerScopeFrom(user, tokenRole);
  if ("ok" in scope) fail(scope);
  const req = parseRequest(data);
  if (!req.ok) fail(req);
  const auth = authorizeTarget(scope, req.target);
  if (!auth.ok) fail(auth);
  const target = auth.target;

  const sentRef = db.collection("sent_notifications").doc();
  const fields: NotificationFields = {
    title: req.title,
    body: req.body,
    type: req.type,
    senderUid: uid,
    senderName: senderNameOf(user || {}),
    senderRole: senderRoleName(user?.role),
    broadcastId: sentRef.id,
  };

  const docs: Record<string, unknown>[] = [];
  let targetName = "";
  let targetDetails = "";
  let targetUid: string | null = null;

  if (target.kind === "all") {
    targetName = "جميع مستخدمي التطبيق (بث عام)";
    targetDetails = "بث مباشر عبر FCM Topic (app_updates) لجميع هواتف Android و iOS";
    docs.push(notificationDoc(fields, "all", "", ""));
  } else if (target.kind === "user") {
    const found = await findUser(db, scope, target);
    if (found) {
      const where = recipientOrgCompany(scope, found);
      targetUid = found.uid;
      targetName = found.name || "مستخدم";
      targetDetails = `مستخدم محدد: ${targetName}`;
      docs.push(notificationDoc(fields, found.uid, where.organizationId, where.companyId,
        found.phone || target.phone || undefined));
    } else if (scope.kind === "global" && target.phone) {
      // Same fallback as the old client: onNotificationCreated resolves phone_<n>.
      targetUid = `phone_${target.phone}`;
      targetName = `رقم الهاتف: ${target.phone}`;
      targetDetails = `مستخدم برقم الهاتف: ${target.phone}`;
      docs.push(notificationDoc(fields, targetUid, "", "", target.phone));
    } else {
      throw new functions.https.HttpsError("not-found", "User not found.", {reason: "not_found"});
    }
  } else {
    const candidates = await listCandidates(db, scope, target);
    const recipients = filterRecipients(scope, candidates);
    if (recipients.length > MAX_RECIPIENTS) tooMany();
    for (const r of recipients) {
      const where = target.kind === "org" || target.kind === "company" ?
        {organizationId: target.org, companyId: target.kind === "company" ? target.company : (r.companyIds[0] ?? "")} :
        recipientOrgCompany(scope, r);
      docs.push(notificationDoc(fields, r.uid, where.organizationId, where.companyId));
    }
    if (target.kind === "role") {
      const label = ROLE_LABELS_AR[target.role] ?? target.role;
      targetName = `فئة: ${label}`;
      targetDetails = `جميع المستخدمين الحاملين لرتبة ${label}`;
    } else {
      const orgName = await nameOf(db.collection("organizations").doc(target.org));
      if (target.kind === "org") {
        targetName = `منظمة: ${orgName}`;
        targetDetails = `جميع أعضاء ومناديب ${orgName}`;
      } else {
        const coName = await nameOf(
          db.collection("organizations").doc(target.org).collection("companies").doc(target.company));
        targetName = `شركة: ${coName}`;
        targetDetails = `جميع مناديب ${coName} (${orgName})`;
      }
    }
  }

  if (docs.length === 0) {
    return {sent: 0, broadcastId: null, targetName};
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  for (const part of chunk(docs, BATCH_SIZE)) {
    const batch = db.batch();
    for (const d of part) batch.set(db.collection("notifications").doc(), {...d, createdAt: now});
    await batch.commit();
  }

  const scopeOrg = scope.kind === "global" ? "" : scope.org;
  const scopeCompany = scope.kind === "company" ? scope.company : "";
  await sentRef.set({
    broadcastId: sentRef.id,
    title: req.title,
    body: req.body,
    type: req.type,
    senderUid: uid,
    senderName: fields.senderName,
    senderRole: fields.senderRole,
    createdBy: uid,
    organizationId: scopeOrg,
    companyId: scopeCompany,
    targetAudience: target.kind,
    targetName,
    targetDetails,
    targetUid,
    targetRole: target.kind === "role" ? target.role : null,
    targetPhone: target.kind === "user" ? (target.phone || null) : null,
    targetOrgId: target.kind === "org" || target.kind === "company" ? target.org : null,
    targetCompanyId: target.kind === "company" ? target.company : null,
    sentCount: docs.length,
    createdAt: now,
  });

  console.log("sendStaffNotification sent", {kind: target.kind, count: docs.length});
  return {sent: docs.length, broadcastId: sentRef.id, targetName};
}

function senderNameOf(user: Record<string, unknown>): string {
  for (const k of ["fullName", "displayName", "name"]) {
    const v = user[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

async function nameOf(ref: admin.firestore.DocumentReference): Promise<string> {
  const snap = await ref.get();
  const d = snap.data() || {};
  const n = d.name ?? d.title;
  return typeof n === "string" && n.trim() ? n.trim() : ref.id;
}

function toCandidates(snaps: Snap[]): Candidate[] {
  const out: Candidate[] = [];
  for (const s of snaps) {
    if (!s.exists) continue;
    const c = candidateFrom(s.id, s.ref.path, s.data() || {});
    if (c) out.push(c);
  }
  return out;
}

async function getDocs(q: admin.firestore.Query): Promise<Snap[]> {
  const snap = await q.limit(MAX_RECIPIENTS + 1).get();
  if (snap.size > MAX_RECIPIENTS) tooMany();
  return snap.docs;
}

function companyDelegates(db: Db, org: string, company: string) {
  return db.collection("organizations").doc(org).collection("companies").doc(company).collection("delegates");
}

async function orgDelegates(db: Db, org: string): Promise<Snap[]> {
  const companies = await db.collection("organizations").doc(org).collection("companies").listDocuments();
  const out: Snap[] = [];
  for (const co of companies) {
    out.push(...await getDocs(co.collection("delegates")));
    if (out.length > MAX_RECIPIENTS * 2) tooMany();
  }
  return out;
}

async function listCandidates(db: Db, scope: CallerScope, target: NotifyTarget): Promise<Candidate[]> {
  if (target.kind === "org") return toCandidates(await orgDelegates(db, target.org));
  if (target.kind === "company") {
    const exists = (await db.collection("organizations").doc(target.org)
      .collection("companies").doc(target.company).get()).exists;
    if (!exists) {
      throw new functions.https.HttpsError("not-found", "Company not found.", {reason: "company_not_found"});
    }
    return toCandidates(await getDocs(companyDelegates(db, target.org, target.company)));
  }
  if (target.kind !== "role") return [];

  if (target.role === "delegate") {
    if (scope.kind === "company") return toCandidates(await getDocs(companyDelegates(db, scope.org, scope.company)));
    if (scope.kind === "org") return toCandidates(await orgDelegates(db, scope.org));
    return toCandidates(await getDocs(db.collectionGroup("delegates")));
  }

  const roles = targetRoleSpellings(target.role) || [];
  let q: admin.firestore.Query = db.collection("users").where("role", "in", roles);
  if (scope.kind === "company") q = q.where("companyUID", "==", scope.company);
  else if (scope.kind === "org") q = q.where("organizationUID", "==", scope.org);
  return toCandidates(await getDocs(q));
}

async function findUser(
  db: Db,
  scope: CallerScope,
  target: {phone: string; uid: string},
): Promise<Candidate | null> {
  const snaps: Snap[] = [];
  if (target.uid) {
    snaps.push(await db.collection("users").doc(target.uid).get());
    snaps.push(...(await db.collectionGroup("delegates").where("uid", "==", target.uid).limit(20).get()).docs);
  }
  if (target.phone) {
    const variants = phoneVariants(target.phone);
    const queries = [
      db.collection("users").where("phoneNumber", "in", variants).limit(10).get(),
      db.collection("users").where("phone", "in", variants).limit(10).get(),
      db.collectionGroup("delegates").where("phoneNumber", "in", variants).limit(20).get(),
      db.collectionGroup("delegates").where("phone", "in", variants).limit(20).get(),
    ];
    for (const r of await Promise.allSettled(queries)) {
      if (r.status === "fulfilled") snaps.push(...r.value.docs);
      else console.error("sendStaffNotification phone query failed");
    }
  }
  // users/ docs come first, so staff win over a delegate doc with the same uid.
  const inScope = filterRecipients(scope, toCandidates(snaps));
  return inScope[0] ?? null;
}
