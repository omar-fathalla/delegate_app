// main v1.14.2 + live web access patterns vs prod ruleset 4daaee78 (live.rules).
import path from 'path';
import { fileURLToPath } from 'url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import fs from 'fs';
import {
  doc, collection, collectionGroup, getDoc, getDocs, setDoc, updateDoc, addDoc,
  writeBatch, query, where, orderBy, limit, increment, serverTimestamp, Timestamp, and, or,
} from 'firebase/firestore';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const FS_PORT = Number(process.env.LOCAL_CI_FIRESTORE_PORT || 8080);
const LIVE_RULES = path.join(ROOT, 'test/rules/ta60/live.rules');
const CAND_RULES = process.env.CAND || path.join(ROOT, 'firestore.rules');

// Deliberate prod-compat rows: 2 class-(c) + silent class-(d) try/catch only.
// Global-staff unbatched approve/provision (FS-11–18) are class (b) and must
// match live ALLOW via globalStaffUnbatched*Ok() — not silenced as (d).
export const DELIBERATE_FIRESTORE_REGRESSIONS = new Set([
  'anonymous (<=v1.14.1) CG delegates phone login query',
  'anonymous (<=v1.14.1) add attendance check-in',
  'delegate CG delegates where nationalityID == own (identifier resolve, try/catch)',
  'delegate users where phoneNumber == supervisorPhone',
  'supervisor users where role in [super-admin...] (notify, try/catch)',
]);

/** Documented dev-security closures (REQUEST CHANGES); not silent prod widenings. */
export function isDeliberateFirestoreRegression(name) {
  return DELIBERATE_FIRESTORE_REGRESSIONS.has(name);
}

/** Same 5 shapes as `buildCustomClaims` → `phoneQueryVariants` in delegate_login_logic.ts (cb3f4e2). */
export function delegateLoginPhoneClaimVariants(normalizedPhone) {
  const variants = new Set();
  if (!normalizedPhone) return [];
  variants.add(normalizedPhone);
  if (normalizedPhone.startsWith('0') && normalizedPhone.length === 11) {
    const withoutZero = normalizedPhone.substring(1);
    variants.add(withoutZero);
    variants.add(`20${withoutZero}`);
    variants.add(`+20${withoutZero}`);
    variants.add(`0020${withoutZero}`);
    variants.add(`+2${normalizedPhone}`);
    variants.add(`002${normalizedPhone}`);
  }
  return [...variants];
}

const DELEGATE_PRIMARY_PHONE = '01000000001';

/**
 * cb3f4e2 getNotifications() phone variations (notification_remote_data_source.dart §5).
 * Includes +20 with leading 0 (+2001…) required for live G5 / phoneNumber ALLOW.
 */
export function getNotificationsPhoneVariations(rawP) {
  const cleanPhone = String(rawP).replace(/\s+/g, '').trim();
  const variations = new Set([cleanPhone]);
  variations.add(cleanPhone.startsWith('0') ? cleanPhone.slice(1) : `0${cleanPhone}`);
  if (!cleanPhone.startsWith('+')) variations.add(`+20${cleanPhone}`);
  if (!cleanPhone.startsWith('+') && cleanPhone.startsWith('0')) {
    variations.add(`+20${cleanPhone.slice(1)}`);
  }
  return [...variations];
}

/** Delegate JWT `phones` claim (5 variants); not Dart-only +2001X leading-zero extras. */
export const DELEGATE_CLAIM_PHONES = delegateLoginPhoneClaimVariants(DELEGATE_PRIMARY_PHONE);

/** Live prod ALLOW counts for counted `list bell:` shapes (excl. G4/G5 extension rows). */
export const BELL_LIVE_ALLOW_TARGETS = {
  delegate: 7,
  supervisor: 7,
  'company-admin': 7,
  hr: 5,
  accountant: 5,
  'org-admin': 5,
  marketing: 7,
  branches_marketing: 8,
  'super-admin': 6,
  tech: 5,
};

const STAFF_BELL_UID = [
  ['sa', 'super-admin'],
  ['ts', 'tech'],
  ['oa', 'org-admin'],
  ['ca', 'company-admin'],
  ['sup', 'supervisor'],
  ['hr', 'hr'],
  ['acc', 'accountant'],
  ['mkt', 'marketing'],
  ['bm', 'branches_marketing'],
];

/** Valid Egyptian 01[0125]XXXXXXXX (11 digits); avoids 010000022-style invalid variant gen. */
const STAFF_PHONE_BY_UID = {
  sa: '01012000001',
  ts: '01012000002',
  oa: '01012000003',
  ca: '01012000004',
  sup: '01011111111',
  hr: '01012000005',
  acc: '01012000006',
  mkt: '01012000007',
  bm: '01012000008',
};

const ORG = 'orgA', CO = 'coA', CO2 = 'coB', ORG2 = 'orgB';
const NOW = Timestamp.now();
const in3d = Timestamp.fromMillis(Date.now() + 3 * 86400e3);
const DOCS = ['personalPhoto','nationalityId','criminalRecord','militaryStatus','qualification','birthCertificate','paymentReceipt']
  .map(k => ({ documentKey: k, documentURL: `https://firebasestorage.googleapis.com/v0/b/x/o/${k}`, documentStatus: 'approved' }));
const DOCS_PENDING = DOCS.map(d => ({ ...d, documentStatus: 'pending' }));

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const u = (id, role, org = ORG, co = CO, extra = {}) => setDoc(doc(db, 'users', id), {
      uid: id, role, organizationUID: org, companyUID: co, email: `${id}@t.test`,
      phoneNumber: STAFF_PHONE_BY_UID[id] ?? `01012000099`, status: 'Approved', ...extra });
    await u('sa', 'super-admin', '', '');
    await u('ts', 'technical_support', '', '');
    await u('oa', 'organization-admin', ORG, '');
    await u('ca', 'company-admin', ORG, CO);
    await u('sup', 'supervisor', ORG, CO, { phoneNumber: '01011111111' });
    await u('hr', 'hr', ORG, CO);
    await u('mkt', 'marketing', ORG, CO);
    await u('mp', 'marketing_promotion', ORG, '');
    await u('bm', 'branches_marketing', ORG, CO);
    await u('acc', 'accountant', ORG, CO);
    await setDoc(doc(db, 'organizations', ORG), { id: ORG, name: 'org a', admins: 1, companies: 2, status: 'active' });
    await setDoc(doc(db, 'organizations', ORG2), { id: ORG2, name: 'org b', admins: 1, companies: 1, status: 'active' });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}`), { name: 'co a', admins: 1, delegates: 1, organizationUID: ORG, type: 'Product', status: 'Active' });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO2}`), { name: 'co b', admins: 1, delegates: 1, organizationUID: ORG, type: 'Product', status: 'Active' });
    const dlg = (id, org, co, nat, phone, extra = {}) => setDoc(doc(db, `organizations/${org}/companies/${co}/delegates/${id}`), {
      uid: id, organizationUID: org, companyUID: co, organizationName: 'org', companyName: 'co', fullName: 'Delegate ' + id,
      phoneNumber: phone, nationalityID: nat, nationalId: nat, status: 'active', statusReason: 'activate', version: 1,
      documents: DOCS, isPrinted: false, hasPendingUpdate: false, receiptCode: 'R-' + id, allReceiptCodes: ['R-' + id],
      createdAt: NOW, updatedAt: NOW, delegatePublicId: 'P-' + id, ...extra });
    await dlg('dlg1', ORG, CO, '29001010101010', '01000000001');
    await setDoc(doc(db, 'users/dlg1'), { uid: 'dlg1', role: 'delegate', organizationUID: ORG, companyUID: CO, phoneNumber: '01000000001' });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/photo_permissions/pp1`), {
      organizationUID: ORG, companyUID: CO, status: 'approved', branchName: 'B1', requestedBy: 'sup',
      startDate: NOW, endDate: in3d, createdAt: NOW,
    });
    await setDoc(doc(db, 'user_wallets/dlg1'), { companyUID: CO, organizationUID: ORG, baseSalary: 100 });
    await dlg('dlg2', ORG, CO2, '29002020202020', '01000000002');
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/requests/r1`), {
      uid: 'r1', actionType: 'update', status: 'pending', targetDelegateId: 'dlg1', organizationUID: ORG, companyUID: CO,
      allReceiptCodes: [], createdAt: NOW, updatedAt: NOW });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/requests/r2`), {
      uid: 'r2', actionType: 'lost_id', status: 'approved', targetDelegateId: 'dlg1', organizationUID: ORG, companyUID: CO,
      isPrinted: false, createdAt: NOW, updatedAt: NOW });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/notifications/cn1`), { title: 't', isRead: false, organizationUID: ORG, companyUID: CO, createdAt: NOW });
    await setDoc(doc(db, 'invites/inv1'), { email: 'new@x.test', status: 'pending', roleToAssign: 'company-admin', organizationId: ORG,
      organizationName: 'org a', companyId: CO, companyName: 'co a', invitedByUid: 'oa', expiresAt: in3d, createdAt: NOW });
    await setDoc(doc(db, 'invite_email_index/new@x.test'), {
      inviteId: 'inv1', organizationUID: ORG, companyUID: CO, role: 'company-admin', status: 'pending',
    });
    await setDoc(doc(db, 'attendance_logs/a1'), { delegateId: 'dlg1', userId: 'dlg1', companyId: CO, organizationId: ORG, type: 'check_in', branchName: 'B1', timestamp: NOW });
    await setDoc(doc(db, 'delegate_requests/req1'), { id: 'req1', supervisorUid: 'sup', companyUID: CO, organizationUID: ORG, status: 'pending',
      requestType: 'new_delegate', fullName: 'X', phoneNumber: '01099999999', nationalId: '29009090909090', receiptCode: 'RC1', createdAt: new Date().toISOString() });
    await setDoc(doc(db, 'leave_requests/l1'), { delegateUid: 'dlg1', companyUID: CO, organizationUID: ORG, status: 'approved', startDate: NOW });
    await setDoc(doc(db, 'delegate_tracking/dlg1'), { delegateId: 'dlg1', companyId: CO, organizationId: ORG, currentStatus: 'inside' });
    await setDoc(doc(db, 'notifications/n1'), { delegateUid: 'dlg1', title: 'x', isRead: false, companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [] });
    const nb = (id, du, extra = {}) => setDoc(doc(db, `notifications/${id}`), {
      delegateUid: du, title: 'bcast', isRead: false, companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [], ...extra,
    });
    await nb('nbAll', 'all');
    await nb('nbCo', `company_${CO}`);
    await nb('nbSup', `supervisor_${CO}`);
    await nb('nbAcs', 'all_company_supervisors');
    await nb('nbHr', 'hr');
    await nb('nbTs', 'technicalSupport');
    await nb('nbMkt', 'marketing');
    await nb('nbBmp', 'branchesMarketingManager');
    await nb('nbOaAdmin', 'organizationAdmin');
    await nb('nbOaDash', 'organization-admin');
    await nb('nbOaUnder', 'organization_admin');
    await nb('nbSaUnder', 'super_admin');
    await nb('nbSaCamel', 'superAdmin');
    await nb('nbSaDash', 'super-admin');
    await nb('nbTsDash', 'technical-support');
    await nb('nbTsRole', 'role_technical_support');
    await nb('nbDel', `delegates_${CO}`);
    await nb('nbPhoneDlg', `phone_dlg1`);
    // Staff G5 (+2001X leading-zero); not in delegate JWT phones claim.
    await setDoc(doc(db, 'notifications/nPhoneDlgPlus20Lead'), {
      phoneNumber: '+2001000000001', delegateUid: 'dlg1', title: 'phone-+20-01', isRead: false,
      companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [],
    });
    for (const p of DELEGATE_CLAIM_PHONES) {
      const slug = p.replace(/[^0-9]/g, '');
      await setDoc(doc(db, `notifications/nbPhField_${slug}`), {
        phoneNumber: p, delegateUid: 'dlg1', title: 'phone-field', isRead: false,
        companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [],
      });
      await setDoc(doc(db, `notifications/nbG5Ph_${slug}`), {
        delegateUid: `phone_${p}`, title: 'g5-phone-tag', isRead: false,
        companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [],
      });
      await setDoc(doc(db, `notifications/nbG5Bare_${slug}`), {
        delegateUid: p, title: 'g5-bare-phone', isRead: false,
        companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [],
      });
    }
    const staffPhoneTag = (uid) => setDoc(doc(db, `notifications/nbPhone_${uid}`), {
      delegateUid: `phone_${uid}`, title: 'phone-tag', isRead: false,
      companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [],
    });
    const staffOwnUidRow = (uid) => setDoc(doc(db, `notifications/nbOwn_${uid}`), {
      delegateUid: uid, title: 'own-uid', isRead: false,
      companyId: CO, organizationId: ORG, createdAt: NOW, deletedBy: [],
    });
    const STAFF_OWN_UID_BELL = new Set(['sa', 'ts', 'oa', 'hr', 'bm', 'mp']);
    for (const uid of ['sa', 'ts', 'oa', 'ca', 'sup', 'hr', 'acc', 'mkt', 'mp', 'bm']) {
      await staffPhoneTag(uid);
      if (STAFF_OWN_UID_BELL.has(uid)) await staffOwnUidRow(uid);
    }
    await setDoc(doc(db, `organizations/${ORG}/tasks/t1`), { companyId: CO, assignedTo: 'dlg1', createdBy: 'sup', title: 't', createdAt: NOW, status: 'pending' });
    await setDoc(doc(db, 'penalties/p1'), { targetDelegateId: 'dlg1', delegateId: 'dlg1', companyId: CO, organizationId: ORG, amount: 10, createdAt: NOW });
    await setDoc(doc(db, 'branches/b1'), { branchName: 'B1', organizationUID: ORG, organizationId: ORG, latitude: 30, longitude: 31 });
    await setDoc(doc(db, 'fcm_tokens/dlg1'), { token: 'tok', platform: 'android' });
    await setDoc(doc(db, 'device_unbind_requests/u1'), { delegateUid: 'dlg1', status: 'pending', companyUID: CO, organizationUID: ORG, companyId: CO, organizationId: ORG });
    await setDoc(doc(db, 'guide_videos/v1'), { title: 'v' });
    await setDoc(doc(db, 'counters/delegates'), { value: 10 });
    await setDoc(doc(db, `organizations/${ORG}/companyRequests/cr1`), { status: 'pending', companyUID: CO, organizationUID: ORG });
    await setDoc(doc(db, `organizations/${ORG}/sent_notifications/sn1`), { title: 'x', createdAt: NOW });
  });
}

const staff = (env, uid, email, extra = {}) => env.authenticatedContext(uid, {
  email: email || `${uid}@t.test`, email_verified: true, firebase: { sign_in_provider: 'password' }, ...extra,
}).firestore();
const delegate = (env) => env.authenticatedContext('dlg1', {
  role: 'delegate', delegateId: 'dlg1', delegateIds: ['dlg1'], orgId: ORG, companyId: CO,
  phones: DELEGATE_CLAIM_PHONES, firebase: { sign_in_provider: 'custom' } }).firestore();
const anon = (env) => env.authenticatedContext('anon1', { firebase: { sign_in_provider: 'anonymous' } }).firestore();

const D = (o, c, id) => `organizations/${o}/companies/${c}/delegates/${id}`;
const attDayStart = () => Timestamp.fromMillis(Date.now() - 86400000);
const attDayEnd = () => Timestamp.fromMillis(Date.now() + 86400000);
const notifList = (db, du, lim = 30) => getDocs(query(
  collection(db, 'notifications'), where('delegateUid', '==', du), limit(lim),
));
const notifListPhoneField = (db, ph, lim = 30) => getDocs(query(
  collection(db, 'notifications'),
  where('phoneNumber', '==', ph),
  limit(lim),
));
const notifListAcs = (db) => getDocs(query(
  collection(db, 'notifications'),
  where('companyId', '==', CO),
  where('delegateUid', '==', 'all_company_supervisors'),
  limit(30),
));

function bellRoleFromCaseName(name) {
  const m = name.match(/^([\w-]+)\s+list bell/);
  return m ? m[1] : null;
}

function isBellCountedCase(name) {
  return name.includes('list bell:') && !name.includes('list bell G4:') && !name.includes('list bell G5:');
}

function cb3f4e2RoleFlags(bellRole, uid) {
  const roleKey = {
    'super-admin': 'super-admin',
    tech: 'technical_support',
    'org-admin': 'organization-admin',
    'company-admin': 'company-admin',
    supervisor: 'supervisor',
    hr: 'hr',
    accountant: 'accountant',
    marketing: 'marketing',
    branches_marketing: 'branches_marketing_manager',
  }[bellRole] ?? bellRole;
  const normalizedRole = roleKey.toLowerCase();
  const isSupervisorOrAdmin = normalizedRole.includes('supervisor')
    || normalizedRole.includes('admin')
    || normalizedRole.includes('company_admin')
    || normalizedRole.includes('company-admin')
    || normalizedRole.includes('super')
    || normalizedRole.includes('support')
    || uid === 'super-admin-login';
  const isDelegate = normalizedRole.includes('delegate')
    || (!isSupervisorOrAdmin && bellRole === 'delegate');
  return { normalizedRole, isSupervisorOrAdmin, isDelegate };
}

function companyUidForStaff(uid, bellRole) {
  if (bellRole === 'org-admin' || bellRole === 'super-admin' || bellRole === 'tech') {
    return '';
  }
  return CO;
}

/** cb3f4e2 getNotifications() §1–4 list shapes (release/1.14.x-supervisor @ cb3f4e2). */
function staffBellShapes(uid, bellRole) {
  const db = (e) => staff(e, uid);
  const shapes = [];
  const push = (label, fn) => shapes.push([
    'NOTIF-READ',
    `${bellRole} list bell: ${label}`,
    (e) => fn(db(e)),
  ]);
  const { normalizedRole, isSupervisorOrAdmin, isDelegate } = cb3f4e2RoleFlags(bellRole, uid);
  const userCompanyId = companyUidForStaff(uid, bellRole);

  if (bellRole === 'org-admin') {
    push('delegateUid==own uid (limit 50)', (d) => getDocs(query(
      collection(d, 'notifications'), where('delegateUid', '==', uid), limit(50),
    )));
    push('delegateUid==all (limit 30)', (d) => notifList(d, 'all'));
    push('delegateUid==phone_<uid> (limit 30)', (d) => notifList(d, `phone_${uid}`));
    for (const alias of ['organizationAdmin', 'organization_admin']) {
      push(`delegateUid==${alias} (limit 30)`, (d) => notifList(d, alias));
    }
    return shapes;
  }

  push('delegateUid==own uid (limit 50)', (d) => getDocs(query(
    collection(d, 'notifications'), where('delegateUid', '==', uid), limit(50),
  )));
  push('delegateUid==all (limit 30)', (d) => notifList(d, 'all'));
  push('delegateUid==phone_<uid> (limit 30)', (d) => notifList(d, `phone_${uid}`));

  if (userCompanyId) {
    push(`delegateUid==company_${userCompanyId} (limit 30)`, (d) => notifList(d, `company_${userCompanyId}`));
    if (isSupervisorOrAdmin) {
      if (bellRole !== 'branches_marketing') {
        push(`delegateUid==supervisor_${userCompanyId} (limit 30)`, (d) => notifList(d, `supervisor_${userCompanyId}`));
      }
      push('companyId+all_company_supervisors (limit 30)', (d) => notifListAcs(d));
    }
    if (isDelegate) {
      push(`delegateUid==delegates_${userCompanyId} (limit 30)`, (d) => notifList(d, `delegates_${userCompanyId}`));
    }
  }

  if (bellRole === 'branches_marketing') {
    for (const r of ['branchesMarketingManager', 'branches_marketing', 'marketing']) {
      push(`delegateUid==${r} (limit 30)`, (d) => notifList(d, r));
    }
    push('delegateUid==hr (limit 30)', (d) => notifList(d, 'hr'));
    return shapes;
  }

  if (bellRole === 'super-admin') {
    for (const r of ['super-admin', 'super_admin', 'superAdmin']) {
      push(`delegateUid==${r} (limit 30)`, (d) => notifList(d, r));
    }
    return shapes;
  }

  if (bellRole === 'tech' || normalizedRole.includes('technical') || normalizedRole.includes('support')) {
    push('delegateUid==technicalSupport (limit 30)', (d) => notifList(d, 'technicalSupport'));
    push('delegateUid==technical-support (limit 30)', (d) => notifList(d, 'technical-support'));
    return shapes;
  }

  if (bellRole === 'hr' || bellRole === 'accountant') {
    push('delegateUid==hr (limit 30)', (d) => notifList(d, 'hr'));
    return shapes;
  }

  if (bellRole === 'marketing') {
    push('companyId+all_company_supervisors (limit 30)', (d) => notifListAcs(d));
    push('delegateUid==marketing (limit 30)', (d) => notifList(d, 'marketing'));
    push('delegateUid==hr (limit 30)', (d) => notifList(d, 'hr'));
    return shapes;
  }
  // supervisor, company-admin (7 each): cb3f4e2 company/supervisor/acs + hr broadcast on live
  push('delegateUid==hr (limit 30)', (d) => notifList(d, 'hr'));
  return shapes;
}

function delegateBellShapes() {
  const shapes = [
    ['NOTIF-READ', 'delegate list bell: delegateUid==own uid (limit 50)', (e) => notifList(delegate(e), 'dlg1', 50)],
    ['NOTIF-READ', 'delegate list bell: delegateUid==phone_dlg1 (limit 30)', (e) => notifList(delegate(e), 'phone_dlg1')],
    ...DELEGATE_CLAIM_PHONES.map((p) => [
      'NOTIF-READ',
      `delegate list bell: phoneNumber==${p} (limit 30)`,
      (e) => notifListPhoneField(delegate(e), p),
    ]),
    ['NOTIF-G5', `delegate list bell G5: delegateUid==delegates_${CO} (limit 30)`, (e) => notifList(delegate(e), `delegates_${CO}`)],
  ];
  for (const p of DELEGATE_CLAIM_PHONES) {
    shapes.push([
      'NOTIF-G5',
      `delegate list bell G5: delegateUid==phone_${p} (limit 30)`,
      (e) => notifList(delegate(e), `phone_${p}`),
    ]);
    shapes.push([
      'NOTIF-G5',
      `delegate list bell G5: delegateUid==${p} (limit 30)`,
      (e) => notifList(delegate(e), p),
    ]);
  }
  return shapes;
}

function staffBellG5Shapes(uid, bellRole) {
  const ph = STAFF_PHONE_BY_UID[uid] ?? '01012000099';
  const db = (e) => staff(e, uid);
  const variants = [...new Set([ph, ...getNotificationsPhoneVariations(ph)])];
  const out = [];
  for (const v of variants) {
    out.push(['NOTIF-G5', `${bellRole} list bell G5: phoneNumber==${v} (limit 30)`, (e) => notifListPhoneField(db(e), v)]);
    out.push(['NOTIF-G5', `${bellRole} list bell G5: delegateUid==phone_${v} (limit 30)`, (e) => notifList(db(e), `phone_${v}`)]);
    out.push(['NOTIF-G5', `${bellRole} list bell G5: delegateUid==${v} (limit 30)`, (e) => notifList(db(e), v)]);
  }
  return out;
}

function buildBellHarnessCases() {
  const out = [...delegateBellShapes()];
  for (const [uid, bellRole] of STAFF_BELL_UID) {
    out.push(...staffBellShapes(uid, bellRole));
    out.push(...staffBellG5Shapes(uid, bellRole));
  }
  return out;
}

function bellCountedQueryFns(bellRole, uid) {
  if (bellRole === 'delegate') {
    return delegateBellShapes()
      .filter(([area, name]) => area === 'NOTIF-READ' && isBellCountedCase(name))
      .map(([, , fn]) => fn);
  }
  return staffBellShapes(uid, bellRole).map(([, , fn]) => fn);
}

/**
 * cb3f4e2 getNotifications(): parallel bell queries (queryAllSettled-style).
 * Returns deduped doc ids plus per-shape hits (queries that returned ≥1 doc).
 */
export async function simulateGetNotifications(env, uid, bellRole) {
  await seed(env);
  const docIds = new Set();
  let queryHits = 0;
  for (const fn of bellCountedQueryFns(bellRole, uid)) {
    try {
      const snap = await fn(env);
      if ((snap?.size ?? 0) > 0) queryHits += 1;
      for (const d of snap?.docs ?? []) {
        docIds.add(d.id);
      }
    } catch (_) {
      // permission-denied / failed query does not drop the rest
    }
  }
  return { uniqueDocs: docIds.size, queryHits, docIds: [...docIds] };
}

export async function simulateGetNotificationsDocCount(env, uid, bellRole) {
  return (await simulateGetNotifications(env, uid, bellRole)).uniqueDocs;
}

export async function runBellGetNotificationsSimulation(testEnv) {
  const roles = [['dlg1', 'delegate'], ...STAFF_BELL_UID];
  const uniqueDocs = {};
  const queryHits = {};
  for (const [uid, bellRole] of roles) {
    const sim = await simulateGetNotifications(testEnv, uid, bellRole);
    uniqueDocs[bellRole] = sim.uniqueDocs;
    queryHits[bellRole] = sim.queryHits;
  }
  return { uniqueDocs, queryHits };
}

export function assertBellAllowCounts(rows) {
  const issues = [];
  for (const [role, target] of Object.entries(BELL_LIVE_ALLOW_TARGETS)) {
    const roleRows = rows.filter(
      (r) => r.area === 'NOTIF-READ' && isBellCountedCase(r.name) && bellRoleFromCaseName(r.name) === role,
    );
    const liveAllow = roleRows.filter((r) => r.live === 'ALLOW').length;
    const candAllow = roleRows.filter((r) => r.cand === 'ALLOW').length;
    if (liveAllow !== target) {
      issues.push(`${role}: live ALLOW ${liveAllow} != target ${target} (${roleRows.length} counted cases)`);
    }
    if (candAllow !== liveAllow) {
      issues.push(`${role}: cand ALLOW ${candAllow} != live ALLOW ${liveAllow}`);
    }
    for (const r of roleRows) {
      if (r.live === 'ALLOW' && r.cand !== 'ALLOW') {
        issues.push(`${r.name}: cand ${r.cand} != live ALLOW`);
      }
      if (r.live === 'ALLOW' && r.cand === 'ALLOW' && r.liveDocCount !== r.candDocCount) {
        issues.push(`${r.name}: live docs ${r.liveDocCount} != cand ${r.candDocCount}`);
      }
    }
  }
  return issues;
}

/** Deduped bell list size after cb3f4e2 getNotifications() merge: live/cand vs prod targets. */
export function assertBellSimulatedDocCounts(liveSim, candSim) {
  const issues = [];
  for (const [role, target] of Object.entries(BELL_LIVE_ALLOW_TARGETS)) {
    const liveDocs = liveSim.uniqueDocs[role];
    const candDocs = candSim.uniqueDocs[role];
    if (liveDocs !== target) {
      issues.push(`${role}: getNotifications() sim live docs ${liveDocs} != target ${target}`);
    }
    if (candDocs !== liveDocs) {
      issues.push(`${role}: getNotifications() sim cand docs ${candDocs} != live ${liveDocs}`);
    }
  }
  return issues;
}

/** Mohamed probe matrix: list paths rules use for bell phone / phone_ tags. */
export const BELL_PHONE_PROBE_MATRIX = [
  {
    shape: 'a',
    label: 'users/{uid} doc + phone_* delegateUid tag',
    probe: 'delegateUid == phone_<staffOrDelegateUid>',
    seed: 'notifications/nbPhone_<uid> with delegateUid phone_<uid>',
  },
  {
    shape: 'b',
    label: 'no users doc + +2001X leading-zero (Dart §5, staff G5)',
    probe: 'phoneNumber == +2001… or delegateUid == phone_+2001…',
    seed: 'notifications/nPhoneDlgPlus20Lead (+2001000000001); staff STAFF_PHONE_BY_UID + getNotificationsPhoneVariations',
  },
  {
    shape: 'c',
    label: '+201 international + users/{uid}.phoneNumber (login claim family)',
    probe: 'phoneNumber == +201… / delegateUid bare +201… (JWT phones claim)',
    seed: `notifications/nbPhField_* per DELEGATE_CLAIM_PHONES (${DELEGATE_CLAIM_PHONES.join(', ')})`,
  },
];
const attOrgBranchToday = (db) => getDocs(query(
  collection(db, 'attendance_logs'),
  where('organizationId', '==', ORG),
  where('branchName', 'in', ['B1']),
  where('timestamp', '>=', attDayStart()),
  where('timestamp', '<', attDayEnd()),
  limit(2000),
));
const cases = [
  ['WEB', 'org-admin get own users doc', e => getDoc(doc(staff(e,'oa'), 'users/oa'))],
  ['WEB', 'org-admin get organization', e => getDoc(doc(staff(e,'oa'), `organizations/${ORG}`))],
  ['WEB', 'org-admin list companies of org', e => getDocs(collection(staff(e,'oa'), `organizations/${ORG}/companies`))],
  ['WEB', 'org-admin update org settings (printingColor)', e => updateDoc(doc(staff(e,'oa'), `organizations/${ORG}`), { printingColor: '#123456', printingTextColor: '#fff', printingCardStyle: 'a', updatedAt: serverTimestamp() })],
  ['WEB', 'org-admin CG delegates where organizationUID', e => getDocs(query(collectionGroup(staff(e,'oa'), 'delegates'), where('organizationUID','==',ORG)))],
  ['WEB', 'org-admin CG delegates org + status active', e => getDocs(query(collectionGroup(staff(e,'oa'), 'delegates'), where('organizationUID','==',ORG), where('status','==','active')))],
  ['WEB', 'org-admin CG delegates org + createdAt>=', e => getDocs(query(collectionGroup(staff(e,'oa'), 'delegates'), where('organizationUID','==',ORG), where('createdAt','>=',Timestamp.fromMillis(0))))],
  ['WEB', 'org-admin CG requests where organizationUID', e => getDocs(query(collectionGroup(staff(e,'oa'), 'requests'), where('organizationUID','==',ORG)))],
  ['WEB', 'org-admin CG requests org + actionType lost_id', e => getDocs(query(collectionGroup(staff(e,'oa'), 'requests'), where('organizationUID','==',ORG), where('actionType','==','lost_id')))],
  ['WEB', 'org-admin mark delegate printed (nested update isPrinted)', e => updateDoc(doc(staff(e,'oa'), D(ORG,CO,'dlg1')), { isPrinted: true, updatedAt: serverTimestamp(), updatedBy: 'oa' })],
  ['WEB', 'org-admin batch print: delegate + lost_id request isPrinted', e => { const db = staff(e,'oa'); const b = writeBatch(db); b.update(doc(db, D(ORG,CO,'dlg1')), { isPrinted: true, updatedAt: serverTimestamp(), updatedBy: 'oa' }); b.update(doc(db, `organizations/${ORG}/companies/${CO}/requests/r2`), { isPrinted: true, updatedAt: serverTimestamp() }); return b.commit(); }],
  ['WEB', 'org-admin create company-admin invite', e => setDoc(doc(staff(e,'oa'), 'invites/invNew'), { email: 'c2@x.test', status: 'pending', roleToAssign: 'company-admin', organizationId: ORG, organizationName: 'org a', companyId: CO, companyName: 'co a', invitedByUid: 'oa', expiresAt: in3d, createdAt: serverTimestamp() })],
  ['WEB', 'org-admin list invites where organizationId', e => getDocs(query(collection(staff(e,'oa'), 'invites'), where('organizationId','==',ORG)))],
  ['WEB', 'org-admin cancel invite (status cancelled)', e => updateDoc(doc(staff(e,'oa'), 'invites/inv1'), { status: 'cancelled', updatedAt: serverTimestamp() })],
  ['WEB', 'org-admin send company notification (nested create)', e => addDoc(collection(staff(e,'oa'), `organizations/${ORG}/companies/${CO}/notifications`), { title: 'x', body: 'y', isRead: false, createdAt: serverTimestamp(), organizationUID: ORG, companyUID: CO })],
  ['WEB', 'org-admin write sent_notifications', e => addDoc(collection(staff(e,'oa'), `organizations/${ORG}/sent_notifications`), { title: 'x', createdAt: serverTimestamp() })],
  ['WEB', 'org-admin create mail doc (invitation email)', e => addDoc(collection(staff(e,'oa'), 'mail'), { to: 'c2@x.test', message: { subject: 's', html: 'h' } })],
  ['WEB', 'org-admin create company (client setDoc)', e => setDoc(doc(staff(e,'oa'), `organizations/${ORG}/companies/coNew`), { name: 'new', organizationUID: ORG, admins: 0, delegates: 0, type: 'Product', status: 'Active', createdAt: serverTimestamp() })],
  ['WEB', 'org-admin read companyRequests', e => getDocs(collection(staff(e,'oa'), `organizations/${ORG}/companyRequests`))],
  ['WEB', 'org-admin read delegate history (nested requests by targetDelegateId)', e => getDocs(query(collection(staff(e,'oa'), `organizations/${ORG}/companies/${CO}/requests`), where('targetDelegateId','==','dlg1')))],
  ['WEB', 'company-admin get own users doc', e => getDoc(doc(staff(e,'ca'), 'users/ca'))],
  ['WEB', 'company-admin CG delegates company + org', e => getDocs(query(collectionGroup(staff(e,'ca'), 'delegates'), where('companyUID','==',CO), where('organizationUID','==',ORG)))],
  ['WEB', 'company-admin CG delegates org + nationalityID (uniqueness check on add delegate)', e => getDocs(query(collectionGroup(staff(e,'ca'), 'delegates'), where('organizationUID','==',ORG), where('nationalityID','==','29002020202020')))],
  ['WEB', 'company-admin CG requests where companyUID', e => getDocs(query(collectionGroup(staff(e,'ca'), 'requests'), where('companyUID','==',CO)))],
  ['WEB', 'company-admin nested delegates allReceiptCodes array-contains-any', e => getDocs(query(collection(staff(e,'ca'), `organizations/${ORG}/companies/${CO}/delegates`), where('allReceiptCodes','array-contains-any',['R-dlg1'])))],
  ['WEB', 'company-admin create new delegate (pending, docs pending) + create request', async e => { const db = staff(e,'ca');
      await setDoc(doc(db, D(ORG,CO,'newD')), { uid: 'newD', delegatePublicId: 'P-new', status: 'pending', statusReason: 'create', hasPendingUpdate: false, version: 0,
        firstName: 'a', fullName: 'a b c', nationalityID: '29003030303030', phoneNumber: '01055555555', position: 'Promoter', gender: 'male', documents: DOCS_PENDING, numberOfDocuments: 7,
        allReceiptCodes: ['RC9'], companyType: 'Product', organizationUID: ORG, organizationName: 'org a', companyUID: CO, companyName: 'co a', createdBy: 'ca', updatedBy: 'ca', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), latestRequestId: 'rq9' });
      return setDoc(doc(db, `organizations/${ORG}/companies/${CO}/requests/rq9`), { uid: 'rq9', actionType: 'create', status: 'pending', targetDelegateId: 'newD', companyUID: CO, organizationUID: ORG, requestedBy: 'ca', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }); }],
  ['WEB', 'company-admin update request + mark delegate pendingAction=update', async e => { const db = staff(e,'ca');
      await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/requests/rqU`), { uid: 'rqU', actionType: 'update', status: 'pending', targetDelegateId: 'dlg1', companyUID: CO, organizationUID: ORG, requestedData: { fullName: 'new name' }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
      return updateDoc(doc(db, D(ORG,CO,'dlg1')), { pendingAction: 'update', hasPendingUpdate: true, latestRequestId: 'rqU', updatedAt: serverTimestamp(), updatedBy: 'ca' }); }],
  ['WEB', 'company-admin cancel request (status cancelled + ttlAt)', e => updateDoc(doc(staff(e,'ca'), `organizations/${ORG}/companies/${CO}/requests/r1`), { status: 'cancelled', updatedAt: serverTimestamp(), ttlAt: in3d })],
  ['WEB', 'company-admin update own company documents', e => updateDoc(doc(staff(e,'ca'), `organizations/${ORG}/companies/${CO}`), { documentUrls: { commercialRegister: 'u1', taxCard: 'u2' }, updatedAt: serverTimestamp() })],
  ['WEB', 'company-admin create companyRequests', e => addDoc(collection(staff(e,'ca'), `organizations/${ORG}/companyRequests`), { status: 'pending', companyUID: CO, organizationUID: ORG, createdAt: serverTimestamp() })],
  ['WEB', 'company-admin create company-admin invite (own company)', e => setDoc(doc(staff(e,'ca'), 'invites/invCa'), { email: 'c3@x.test', status: 'pending', roleToAssign: 'company-admin', organizationId: ORG, organizationName: 'org a', companyId: CO, companyName: 'co a', invitedByUid: 'ca', expiresAt: in3d, createdAt: serverTimestamp() })],
  ['WEB', 'company-admin read + mark company notification read', async e => { const db = staff(e,'ca'); await getDocs(collection(db, `organizations/${ORG}/companies/${CO}/notifications`)); return updateDoc(doc(db, `organizations/${ORG}/companies/${CO}/notifications/cn1`), { isRead: true }); }],
  ['WEB', 'invitee (no users doc) get invite by id', e => getDoc(doc(staff(e,'newu','new@x.test'), 'invites/inv1'))],
  ['WEB', 'invitee claimInvite$ client batch (member + users + admins+1 + invite claimed)', e => { const db = staff(e,'newu','new@x.test'); const b = writeBatch(db);
      b.set(doc(db, `organizations/${ORG}/companies/${CO}/members/newu`), { role: 'company-admin', status: 'active', displayName: 'n', createdAt: serverTimestamp(), invitedBy: 'oa' });
      b.set(doc(db, 'users/newu'), { uid: 'newu', email: 'new@x.test', displayName: 'n', phoneNumber: null, role: 'company-admin', emailVerified: true, organizationUID: ORG, organizationName: 'org a', companyUID: CO, companyName: 'co a', status: 'Approved', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
      b.update(doc(db, `organizations/${ORG}/companies/${CO}`), { admins: increment(1), updatedAt: serverTimestamp() });
      b.update(doc(db, 'invites/inv1'), { status: 'claimed', claimedAt: serverTimestamp(), claimedByUid: 'newu', claimedByEmail: 'new@x.test', updatedAt: serverTimestamp() });
      return b.commit(); }],
  ['WEB', 'super-admin list organizations', e => getDocs(collection(staff(e,'sa'), 'organizations'))],
  ['WEB', 'super-admin write guide_videos', e => setDoc(doc(staff(e,'sa'), 'guide_videos/v2'), { title: 'v2', url: 'u' })],
  ['WEB', 'super-admin CG delegates all', e => getDocs(collectionGroup(staff(e,'sa'), 'delegates'))],
  ['WEB', 'any signed-in read guide_videos', e => getDocs(collection(staff(e,'ca'), 'guide_videos'))],
  ['APP-D', 'delegate CG delegates where phoneNumber == own phone (profile load)', e => getDocs(query(collectionGroup(delegate(e), 'delegates'), where('phoneNumber','==','01000000001')))],
  ['APP-D', 'delegate get own nested delegate doc', e => getDoc(doc(delegate(e), D(ORG,CO,'dlg1')))],
  ['APP-D', 'delegate CG delegates where nationalityID == own (identifier resolve, try/catch)', e => getDocs(query(collectionGroup(delegate(e), 'delegates'), where('nationalityID','==','29001010101010'), limit(10)))],
  ['APP-D', 'delegate check-in add attendance_logs', e => addDoc(collection(delegate(e), 'attendance_logs'), { delegateId: 'dlg1', userId: 'dlg1', companyId: CO, organizationId: ORG, timestamp: serverTimestamp(), type: 'check_in', location: { latitude: 30, longitude: 31 }, deviceInfo: { model: 'x' }, branchName: 'B1', delegateName: 'D', phoneNumber: '01000000001', companyName: 'co a' })],
  ['APP-D', 'delegate check-out batch (set out + update check-in)', e => { const db = delegate(e); const b = writeBatch(db); const out = doc(collection(db, 'attendance_logs'));
      b.set(out, { delegateId: 'dlg1', userId: 'dlg1', companyId: CO, organizationId: ORG, timestamp: serverTimestamp(), type: 'check_out', location: { latitude: 30, longitude: 31 }, relatedCheckInId: 'a1', branchName: 'B1' });
      b.update(doc(db, 'attendance_logs/a1'), { checkOutTime: serverTimestamp(), checkOutLocation: { latitude: 30, longitude: 31 }, checkOutDocId: out.id }); return b.commit(); }],
  ['APP-D', 'delegate get own check-in doc', e => getDoc(doc(delegate(e), 'attendance_logs/a1'))],
  ['APP-D', 'delegate query own open check-ins (delegateId+type+branchName)', e => getDocs(query(collection(delegate(e), 'attendance_logs'), where('delegateId','==','dlg1'), where('type','==','check_in'), where('branchName','==','B1'), limit(5)))],
  ['APP-D', 'delegate history attendance where delegateId in [ids]', e => getDocs(query(collection(delegate(e), 'attendance_logs'), where('delegateId','in',['dlg1'])))],
  ['APP-D', 'delegate notify supervisor (notifications add, delegateUid=supervisor uid)', e => addDoc(collection(delegate(e), 'notifications'), { title: 't', body: 'b', type: 'attendance', attendanceType: 'check_in', companyId: CO, organizationId: ORG, branchName: 'B1', targetDelegateId: 'dlg1', targetDelegateName: 'D', senderName: 'D', senderRole: 'delegate', delegateUid: 'sup', isRead: false, read: false, createdAt: NOW, deletedBy: [] })],
  ['APP-D', 'delegate broadcast notification (delegateUid=supervisor_<co>)', e => addDoc(collection(delegate(e), 'notifications'), { title: 't', body: 'b', type: 'attendance', attendanceType: 'check_in', companyId: CO, organizationId: ORG, branchName: 'B1', targetDelegateId: 'dlg1', targetDelegateName: 'D', senderName: 'D', senderRole: 'delegate', delegateUid: `supervisor_${CO}`, isRead: false, read: false, createdAt: NOW, deletedBy: [] })],
  ['APP-D', 'delegate read own notifications (delegateUid == uid)', e => getDocs(query(collection(delegate(e), 'notifications'), where('delegateUid','==','dlg1')))],
  ['APP-D', 'delegate tracking set merge', e => setDoc(doc(delegate(e), 'delegate_tracking/dlg1'), { delegateId: 'dlg1', delegateName: 'D', delegatePhone: '01000000001', companyId: CO, organizationId: ORG, branchId: 'b1', branchName: 'B1', currentStatus: 'inside', lastLatitude: 30, lastLongitude: 31, isOnline: true, lastUpdated: serverTimestamp(), checkInTime: NOW }, { merge: true })],
  ['APP-D', 'delegate tracking breadcrumb add', e => addDoc(collection(delegate(e), 'delegate_tracking/dlg1/breadcrumbs'), { latitude: 30, longitude: 31, timestamp: serverTimestamp(), speed: 0, distanceMeters: 5, isInside: true })],
  ['APP-D', 'delegate save FCM token (fcm_tokens/{uid} set)', e => setDoc(doc(delegate(e), 'fcm_tokens/dlg1'), { token: 't2', updatedAt: serverTimestamp(), platform: 'android' })],
  ['APP-D', 'delegate clear re-login flag on own delegate doc', e => updateDoc(doc(delegate(e), D(ORG,CO,'dlg1')), { requireReLogin: false, reLoginCompletedAt: serverTimestamp() })],
  ['APP-D', 'delegate read org tasks (main shape: companyId AND or(assignedTo) orderBy createdAt)', e => getDocs(query(collection(delegate(e), `organizations/${ORG}/tasks`), and(where('companyId','==',CO), or(where('assignedTo','==','dlg1'), where('assignedTo','==','all'))), orderBy('createdAt','desc')))],
  ['APP-D', 'delegate read own approved leaves', e => getDocs(query(collection(delegate(e), 'leave_requests'), where('delegateUid','==','dlg1'), where('status','==','approved')))],
  ['APP-D', 'delegate create leave request', e => addDoc(collection(delegate(e), 'leave_requests'), { delegateUid: 'dlg1', delegateName: 'D', companyUID: CO, organizationUID: ORG, status: 'pending', type: 'annual', startDate: NOW, endDate: NOW, daysCount: 1, createdAt: serverTimestamp() })],
  ['APP-D', 'delegate read root branches', e => getDocs(collection(delegate(e), 'branches'))],
  ['APP-D', 'delegate read own penalties', e => getDocs(query(collection(delegate(e), 'penalties'), where('targetDelegateId','==','dlg1')))],
  ['APP-D', 'delegate create device_unbind_request', e => addDoc(collection(delegate(e), 'device_unbind_requests'), { delegateUid: 'dlg1', delegateName: 'D', companyUID: CO, organizationUID: ORG, status: 'pending', reason: 'new phone', createdAt: serverTimestamp() })],
  ['APP-D', 'delegate get supervisor users doc (home screen)', e => getDoc(doc(delegate(e), 'users/sup'))],
  ['APP-D', 'delegate users where phoneNumber == supervisorPhone', e => getDocs(query(collection(delegate(e), 'users'), where('phoneNumber','==','01011111111')))],
  ['APP-D', 'delegate create photo_permission request (nested)', e => addDoc(collection(delegate(e), `organizations/${ORG}/companies/${CO}/photo_permissions`), { delegateUid: 'dlg1', delegateName: 'D', organizationUID: ORG, companyUID: CO, status: 'pending', createdAt: serverTimestamp(), branchName: 'B1' })],
  ['APP-D', 'delegate security_audit_logs add', e => addDoc(collection(delegate(e), 'security_audit_logs'), { actionType: 'x', delegateUid: 'dlg1', companyUID: CO, organizationUID: ORG, timestamp: serverTimestamp(), status: 'executed' })],
  ['APP-S', 'supervisor get own users doc', e => getDoc(doc(staff(e,'sup'), 'users/sup'))],
  ['APP-S', 'supervisor clear own re-login flag (users update)', e => updateDoc(doc(staff(e,'sup'), 'users/sup'), { requireReLogin: false, reLoginCompletedAt: serverTimestamp() })],
  ['APP-S', 'supervisor list nested delegates of own company', e => getDocs(collection(staff(e,'sup'), `organizations/${ORG}/companies/${CO}/delegates`))],
  ['APP-S', 'supervisor CG delegates where companyUID', e => getDocs(query(collectionGroup(staff(e,'sup'), 'delegates'), where('companyUID','==',CO)))],
  ['APP-S', 'supervisor CG delegates phoneNumber dup-check (try/catch)', e => getDocs(query(collectionGroup(staff(e,'sup'), 'delegates'), where('phoneNumber','==','01000000002'), limit(1)))],
  ['APP-S', 'supervisor CG delegates nationalId dup-check (try/catch)', e => getDocs(query(collectionGroup(staff(e,'sup'), 'delegates'), where('nationalId','==','29002020202020'), limit(1)))],
  ['APP-S', 'supervisor CG delegates receiptCode dup-check (try/catch)', e => getDocs(query(collectionGroup(staff(e,'sup'), 'delegates'), where('receiptCode','==','R-dlg2'), limit(1)))],
  ['APP-S', 'supervisor delegate_requests where receiptCode (try/catch)', e => getDocs(query(collection(staff(e,'sup'), 'delegate_requests'), where('companyUID', '==', CO), where('receiptCode', '==', 'RC1')))],
  ['APP-S', 'supervisor submit new_delegate request (delegate_requests set, v1.14.2 toMap)', e => setDoc(doc(staff(e,'sup'), 'delegate_requests/reqNew'), {
      id: 'reqNew', supervisorUid: 'sup', supervisorName: 'S', supervisorPhone: '01011111111', companyUID: CO, companyName: 'co a', organizationUID: ORG, organizationName: 'org a',
      firstName: 'a', secondName: 'b', thirdName: 'c', fullName: 'a b c', phoneNumber: '01077777777', nationalId: '29007070707070', profileImageUrl: 'https://firebasestorage.googleapis.com/x',
      nationalIdFrontUrl: 'https://firebasestorage.googleapis.com/f', nationalIdBackUrl: 'https://firebasestorage.googleapis.com/b', paymentMethod: 'free_promotion', receiptCode: null, receiptImageUrl: null,
      subscriptionCycle: '2026-H2', cycleStartDate: '2026-07-01T00:00:00.000', cycleEndDate: '2026-12-31T00:00:00.000', fee: 0, remainingMonths: 2, status: 'pending', requestType: 'new_delegate',
      existingDelegateUid: null, currentOrganizationName: null, rejectionReason: null, reviewedBy: null, reviewedAt: null, createdAt: new Date().toISOString() })],
  ['APP-S', 'supervisor list own delegate_requests (supervisorUid)', e => getDocs(query(collection(staff(e,'sup'), 'delegate_requests'), where('supervisorUid','==','sup')))],
  ['APP-S', 'supervisor notify staff (notifications add delegateUid=superAdmin role key)', e => addDoc(collection(staff(e,'sup'), 'notifications'), { delegateUid: 'superAdmin', title: 't', body: 'b', type: 'delegate_subscription_request', requestId: 'reqNew', senderName: 'S', senderRole: 'supervisor', createdAt: serverTimestamp(), isRead: false, targetRoles: ['superAdmin','technicalSupport'] })],
  ['APP-S', 'supervisor users where role in [super-admin...] (notify, try/catch)', e => getDocs(query(collection(staff(e,'sup'), 'users'), where('role','in',['super-admin','super_admin','superAdmin','technical_support'])))],
  ['APP-S', 'supervisor attendance_logs company + time range', e => getDocs(query(collection(staff(e,'sup'), 'attendance_logs'), where('companyId','==',CO), where('timestamp','>=',Timestamp.fromMillis(0))))],
  ['APP-S', 'supervisor attendance_logs organizationId + branchName (no company filter) + ts range + limit 2000 (exact main shape)', e => getDocs(query(collection(staff(e,'sup'), 'attendance_logs'), where('organizationId','==',ORG), where('branchName','in',['B1']), where('timestamp','>=',Timestamp.fromMillis(Date.now()-86400000)), where('timestamp','<',Timestamp.fromMillis(Date.now()+86400000)), limit(2000)))],
  ['APP-S', 'supervisor create task (org tasks)', e => addDoc(collection(staff(e,'sup'), `organizations/${ORG}/tasks`), { companyId: CO, assignedTo: 'dlg1', createdBy: 'sup', title: 'new', status: 'pending', createdAt: serverTimestamp() })],
  ['APP-S', 'supervisor list org tasks by companyId', e => getDocs(query(collection(staff(e,'sup'), `organizations/${ORG}/tasks`), where('companyId','==',CO)))],
  ['APP-S', 'supervisor create penalty', e => addDoc(collection(staff(e,'sup'), 'penalties'), { targetDelegateId: 'dlg1', delegateId: 'dlg1', companyId: CO, organizationId: ORG, amount: 5, reason: 'late', createdById: 'sup', createdAt: serverTimestamp() })],
  ['APP-S', 'supervisor list penalties by companyId', e => getDocs(query(collection(staff(e,'sup'), 'penalties'), where('companyId','==',CO)))],
  ['APP-S', 'supervisor delegate_tracking list by companyId', e => getDocs(query(collection(staff(e,'sup'), 'delegate_tracking'), where('companyId','==',CO)))],
  ['APP-S', 'supervisor read photo_permissions nested', e => getDocs(collection(staff(e,'sup'), `organizations/${ORG}/companies/${CO}/photo_permissions`))],
  ['APP-S', 'supervisor read own notifications (delegateUid == uid)', e => getDocs(query(collection(staff(e,'sup'), 'notifications'), where('delegateUid','==','sup')))],
  ['APP-S', 'supervisor read company broadcast notifications (delegateUid in [supervisor_co, company_co])', e => getDocs(query(collection(staff(e,'sup'), 'notifications'), where('delegateUid','in',[`supervisor_${CO}`, `company_${CO}`, 'all_company_supervisors'])))],
  ['APP-S', 'supervisor update delegate doc status (suspend)', e => updateDoc(doc(staff(e,'sup'), D(ORG,CO,'dlg1')), { status: 'suspended', statusReason: 'suspend', updatedAt: serverTimestamp() })],
  ['APP-S', 'hr list leave_requests by companyUID', e => getDocs(query(collection(staff(e,'hr'), 'leave_requests'), where('companyUID','==',CO)))],
  ['APP-S', 'hr approve leave request', e => updateDoc(doc(staff(e,'hr'), 'leave_requests/l1'), { status: 'approved', reviewedBy: 'hr', reviewedAt: serverTimestamp() })],
  ['APP-S', 'hr list device_unbind_requests by companyUID+status', e => getDocs(query(collection(staff(e,'hr'), 'device_unbind_requests'), where('companyUID','==',CO), where('status','==','pending')))],
  ['APP-S', 'hr approve device_unbind_request', e => updateDoc(doc(staff(e,'hr'), 'device_unbind_requests/u1'), { status: 'approved', reviewedBy: 'hr', reviewedAt: serverTimestamp() })],
  ['APP-S', 'hr attendance_logs companyId + timestamp', e => getDocs(query(collection(staff(e,'hr'), 'attendance_logs'), where('companyId','==',CO), where('timestamp','>=',Timestamp.fromMillis(0))))],
  ['APP-S', 'marketing attendance_logs organizationId + branchName + ts range + limit 2000 (exact main shape)', e => getDocs(query(collection(staff(e,'mkt'), 'attendance_logs'), where('organizationId','==',ORG), where('branchName','in',['B1']), where('timestamp','>=',Timestamp.fromMillis(Date.now()-86400000)), where('timestamp','<',Timestamp.fromMillis(Date.now()+86400000)), limit(2000)))],
  ['APP-S', 'marketing CG photo_permissions org filter', e => getDocs(query(collectionGroup(staff(e,'mkt'), 'photo_permissions'), where('organizationUID','==',ORG)))],
  ['RC', 'marketing_promotion CG photo_permissions org (getOngoingPermissions shape)', e => getDocs(query(collectionGroup(staff(e,'mp'), 'photo_permissions'), where('organizationUID','==',ORG)))],
  ['RC', 'branchesMarketingManager CG photo_permissions org filter', e => getDocs(query(collectionGroup(staff(e,'bm'), 'photo_permissions'), where('organizationUID','==',ORG)))],
  ['RC', 'hr payroll user_wallets where companyUID', e => getDocs(query(collection(staff(e,'hr'), 'user_wallets'), where('companyUID','==',CO)))],
  ['RC', 'accountant financial delegate_requests where organizationUID', e => getDocs(query(collection(staff(e,'acc'), 'delegate_requests'), where('organizationUID','==',ORG)))],
  ['RC', 'supervisor registration nationalId dup-check listen (nationalId query)', e => getDocs(query(collectionGroup(staff(e,'sup'), 'delegates'), where('nationalId','==','29009090909090'), limit(1)))],
  ['APP-S', 'branches_marketing attendance org + branch + ts range + limit 2000 (exact main shape)', e => getDocs(query(collection(staff(e,'bm'), 'attendance_logs'), where('organizationId','==',ORG), where('branchName','in',['B1']), where('timestamp','>=',Timestamp.fromMillis(Date.now()-86400000)), where('timestamp','<',Timestamp.fromMillis(Date.now()+86400000)), limit(2000)))],
  ['APP-S', 'branches_marketing create root branch', e => addDoc(collection(staff(e,'bm'), 'branches'), { branchName: 'B2', organizationUID: ORG, organizationId: ORG, latitude: 30, longitude: 31 })],
  ['APP-S', 'tech support list delegate_requests pending', e => getDocs(query(collection(staff(e,'ts'), 'delegate_requests'), where('status','==','pending')))],
  ['APP-S', 'tech support approve request (update status approved)', e => updateDoc(doc(staff(e,'ts'), 'delegate_requests/req1'), { status: 'approved', reviewedBy: 'ts', reviewedAt: new Date().toISOString() })],
  ['APP-S', 'super-admin approve request (update status approved, main step 1)', e => updateDoc(doc(staff(e,'sa'), 'delegate_requests/req1'), { status: 'approved', reviewedBy: 'sa', reviewedAt: new Date().toISOString() })],
  ['APP-S', 'super-admin provision delegate set(merge) status active (main step 2c, unbatched)', e => setDoc(doc(staff(e,'sa'), `organizations/${ORG}/companies/${CO}/delegates/newdlg`), { uid: 'newdlg', name: 'N', status: 'active', organizationUID: ORG, companyUID: CO, phoneNumber: '01000000099', nationalityID: '29901010100099', registeredVia: 'mobile_app' }, { merge: true })],
  ['APP-S', 'tech support provision delegate set(merge) status active (main step 2c, unbatched)', e => setDoc(doc(staff(e,'ts'), `organizations/${ORG}/companies/${CO}/delegates/newdlg`), { uid: 'newdlg', name: 'N', status: 'active', organizationUID: ORG, companyUID: CO, phoneNumber: '01000000099', nationalityID: '29901010100099', registeredVia: 'mobile_app' }, { merge: true })],
  ['APP-S', 'super-admin users list all (collections screen)', e => getDocs(collection(staff(e,'sa'), 'users'))],
  ['APP-S', 'any staff users list all (private label perms: users get())', e => getDocs(query(collection(staff(e,'mkt'), 'users'), where('organizationUID', '==', ORG)))],
  ['APP-S', 'staff read root branches', e => getDocs(collection(staff(e,'hr'), 'branches'))],
  ['APP-S', 'supervisor CG companies where documentId', e => getDocs(query(collectionGroup(staff(e,'sup'), 'companies')))],
  ...['PENDING_BRANCHES_MARKETING','ISSUED'].map(st => ['URG', `supervisor penalties set() PenaltyModel status ${st}`, e => { const db = staff(e,'sup'); const ref = doc(collection(db,'penalties'));
      return setDoc(ref, { penaltyId: ref.id, companyId: CO, companyName: 'co a', branchId: 'b1', branchName: 'B1', createdById: 'sup', createdByName: 'Sup', title: 'تأخير', category: 'PROTOCOL_BREACH',
        incidentDescription: 'desc', fineAmount: 100, currency: 'EGP', status: st, evidenceFiles: [{ fileUrl: 'https://x/y.jpg', fileName: 'y.jpg', fileType: 'image' }],
        targetDelegateId: 'dlg1', targetDelegateName: 'Delegate dlg1', isRepeated: false, isConfidential: false, createdAt: NOW, updatedAt: NOW }); }]),
  ...['dlg1','sup','ca','company_coA','supervisor_coA','all_company_supervisors','branchesMarketingManager','branches_marketing','marketing','organizationAdmin','super-admin','superAdmin','super_admin','technicalSupport','technical_support']
    .map(t => ['URG', `supervisor penalty notification -> delegateUid=${t}`, e => addDoc(collection(staff(e,'sup'),'notifications'), { title: 't', body: 'b', type: 'penalty', penaltyId: 'p9', companyId: CO, companyName: 'co a', branchId: 'b1', branchName: 'B1',
      targetDelegateId: 'dlg1', targetDelegateName: 'D', fineAmount: 100, category: 'PROTOCOL_BREACH', incidentDescription: 'd', createdById: 'sup', createdByName: 'Sup', senderName: 'Sup', senderRole: 'supervisor', delegateUid: t, isRead: false, read: false, createdAt: Timestamp.now(), deletedBy: [] })]),
  ['URG', 'supervisor users where companyUID == co (penalty notify lookup)', e => getDocs(query(collection(staff(e,'sup'),'users'), where('companyUID','==',CO)))],
  ...['sup','supervisor_coA','company_coA','all_company_supervisors'].map(t => ['URG', `delegate attendance_check_in notification -> delegateUid=${t}`, e => addDoc(collection(delegate(e),'notifications'), { title: 't', body: 'b', type: 'attendance_check_in', attendanceType: 'check_in',
      companyId: CO, organizationId: ORG, branchName: 'B1', targetDelegateId: 'dlg1', targetDelegateName: 'D', senderName: 'D', senderRole: 'delegate', delegateUid: t, isRead: false, read: false, createdAt: Timestamp.now(), deletedBy: [] })]),
  ['URG', 'delegate users where companyUID == co (attendance notify lookup, try/catch)', e => getDocs(query(collection(delegate(e),'users'), where('companyUID','==',CO)))],
  ['URG', 'supervisor read company broadcasts delegateUid in [supervisor_co, company_co, all_company_supervisors]', e => getDocs(query(collection(staff(e,'sup'),'notifications'), where('delegateUid','in',['supervisor_coA','company_coA','all_company_supervisors'])))],
  ...['ts','sa'].flatMap(r => [
    ['URG', `${r} approve new delegate step1 update delegate_requests approved`, e => updateDoc(doc(staff(e,r),'delegate_requests/req1'), { status: 'approved', reviewedBy: r, reviewedAt: new Date().toISOString() })],
    ['URG', `${r} approve step2a company set(merge)`, e => setDoc(doc(staff(e,r),`organizations/${ORG}/companies/${CO}`), { id: CO, uid: CO, name: 'co a', organizationUID: ORG, organizationName: 'org a', updatedAt: serverTimestamp() }, { merge: true })],
    ['URG', `${r} approve step2b admins/sup set(merge)`, e => setDoc(doc(staff(e,r),`organizations/${ORG}/companies/${CO}/admins/sup`), { uid: 'sup', name: 'Sup', phone: '01011111111', role: 'company-admin', companyUID: CO, companyName: 'co a', organizationUID: ORG, organizationName: 'org a', updatedAt: serverTimestamp() }, { merge: true })],
    ['URG', `${r} approve step2c delegate set(merge) active`, e => setDoc(doc(staff(e,r),`organizations/${ORG}/companies/${CO}/delegates/req1`), { uid: 'req1', fullName: 'X', status: 'active', organizationUID: ORG, companyUID: CO, organizationName: 'org a', companyName: 'co a', phoneNumber: '01099999999', nationalityID: '29009090909090', nationalId: '29009090909090', receiptCode: 'RC1', position: 'org a', originOrganizationName: 'org a', isExternal: false, registeredVia: 'mobile_app', createdAt: serverTimestamp() }, { merge: true })],
    ['URG', `${r} approve notify supervisor`, e => addDoc(collection(staff(e,r),'notifications'), { title: 't', body: 'b', type: 'subscription', delegateUid: 'sup', isRead: false, createdAt: serverTimestamp(), deletedBy: [] })],
  ]),
  ['URG', 'org-admin CG requests org + status pending (dashboard)', e => getDocs(query(collectionGroup(staff(e,'oa'),'requests'), where('organizationUID','==',ORG), where('status','==','pending')))],
  ['URG', 'org-admin CG delegates org + nationalityID (dup check)', e => getDocs(query(collectionGroup(staff(e,'oa'),'delegates'), where('organizationUID','==',ORG), where('nationalityID','==','29002020202020')))],
  ['URG', 'company-admin nested company notifications list', e => getDocs(collection(staff(e,'ca'), `organizations/${ORG}/companies/${CO}/notifications`))],
  ['URG', 'org-admin nested company notifications list', e => getDocs(collection(staff(e,'oa'), `organizations/${ORG}/companies/${CO}/notifications`))],
  ...buildBellHarnessCases(),
  ['ATT-READ', 'marketing_promotion attendance org+branchName+today (limit 2000)', e => attOrgBranchToday(staff(e, 'mp'))],
  ['ATT-READ', 'marketing attendance org+branchName+today (limit 2000, chain shape)', e => attOrgBranchToday(staff(e, 'mkt'))],
  ['ATT-READ', 'branches_marketing attendance org+branchName+today (limit 2000)', e => attOrgBranchToday(staff(e, 'bm'))],
  ['URG', 'tech support follow-up write admins/sup merge (approve step 2b)', e => setDoc(doc(staff(e,'ts'), `organizations/${ORG}/companies/${CO}/admins/sup`), { uid: 'sup', name: 'Sup', phone: '01011111111', role: 'company-admin', companyUID: CO, companyName: 'co a', organizationUID: ORG, organizationName: 'org a', updatedAt: serverTimestamp() }, { merge: true })],
  ['APP-OLD', 'anonymous (<=v1.14.1) CG delegates phone login query', e => getDocs(query(collectionGroup(anon(e), 'delegates'), where('phoneNumber','==','01000000001')))],
  ['APP-OLD', 'anonymous (<=v1.14.1) add attendance check-in', e => addDoc(collection(anon(e), 'attendance_logs'), { delegateId: 'dlg1', companyId: CO, organizationId: ORG, type: 'check_in', branchName: 'B1', timestamp: serverTimestamp() })],
];

async function runAll(env, label) {
  const out = [];
  for (const [, name, fn] of cases) {
    await seed(env);
    let res;
    let docCount;
    try {
      const snap = await fn(env);
      docCount = snap?.size ?? (snap?.docs ? snap.docs.length : undefined);
      res = 'ALLOW';
    } catch (e) {
      res = 'DENY';
      docCount = undefined;
      (globalThis.MSG ||= {})[label + '|' + name] = String(e.message).replace(/\s+/g, ' ').slice(0, 600);
      if (!String(e.code || e.message).includes('permission')) res = 'ERR:' + String(e.code || e.message).slice(0, 80);
    }
    out.push({ res, docCount });
  }
  return out;
}

const mk = (pid, file) => initializeTestEnvironment({
  projectId: pid,
  firestore: { rules: fs.readFileSync(file, 'utf8'), host: '127.0.0.1', port: FS_PORT },
});

export async function runFirestoreCompatHarness() {
  const live = await mk('demo-ta60-live', LIVE_RULES);
  const cand = await mk('demo-ta60-cand', CAND_RULES);
  const rl = await runAll(live, 'live');
  const rd = await runAll(cand, 'cand');
  const bellLiveSim = await runBellGetNotificationsSimulation(live);
  const bellCandSim = await runBellGetNotificationsSimulation(cand);
  await live.cleanup();
  await cand.cleanup();
  const rows = cases.map((c, i) => ({
    area: c[0],
    name: c[1],
    live: rl[i].res,
    cand: rd[i].res,
    liveDocCount: rl[i].docCount,
    candDocCount: rd[i].docCount,
    regression: rl[i].res === 'ALLOW' && rd[i].res !== 'ALLOW',
    deliberate: isDeliberateFirestoreRegression(c[1]),
    candMsg: (globalThis.MSG || {})['cand|' + c[1]],
  }));
  const unexpected = rows.filter(r => r.regression && !r.deliberate);
  const deliberate = rows.filter(r => r.regression && r.deliberate);
  const isExprLimitMsg = (msg) => /maximum of 1000 expressions|limit exceeded/i.test(String(msg || ''));
  const bellCountIssues = assertBellAllowCounts(rows);
  const bellSimulationIssues = assertBellSimulatedDocCounts(bellLiveSim, bellCandSim);
  return {
    rows,
    total: rows.length,
    deliberate,
    unexpected,
    exprLimit: unexpected.filter(r => isExprLimitMsg(r.candMsg)),
    bellCountIssues,
    bellLiveSim,
    bellCandSim,
    bellSimulationIssues,
  };
}