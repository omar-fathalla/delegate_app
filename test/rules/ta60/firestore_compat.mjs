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

export const DELIBERATE_FIRESTORE_REGRESSIONS = new Set([
  'supervisor update delegate doc status (suspend)',
  'any staff users list all (private label perms: users get())',
  'anonymous (<=v1.14.1) CG delegates phone login query',
  'anonymous (<=v1.14.1) add attendance check-in',
]);

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
      uid: id, role, organizationUID: org, companyUID: co, email: `${id}@t.test`, phoneNumber: `0100000${id.length}${id.length}`, status: 'Approved', ...extra });
    await u('sa', 'super-admin', '', '');
    await u('ts', 'technical_support', '', '');
    await u('oa', 'organization-admin', ORG, '');
    await u('ca', 'company-admin', ORG, CO);
    await u('sup', 'supervisor', ORG, CO, { phoneNumber: '01011111111' });
    await u('hr', 'hr', ORG, CO);
    await u('mkt', 'marketing', ORG, '');
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
    await nb('nbDel', `delegates_${CO}`);
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

const staff = (env, uid, email) => env.authenticatedContext(uid, { email: email || `${uid}@t.test`, email_verified: true, firebase: { sign_in_provider: 'password' } }).firestore();
const delegate = (env) => env.authenticatedContext('dlg1', {
  role: 'delegate', delegateId: 'dlg1', delegateIds: ['dlg1'], orgId: ORG, companyId: CO,
  phones: ['01000000001', '+201000000001', '201000000001'], firebase: { sign_in_provider: 'custom' } }).firestore();
const anon = (env) => env.authenticatedContext('anon1', { firebase: { sign_in_provider: 'anonymous' } }).firestore();

const D = (o, c, id) => `organizations/${o}/companies/${c}/delegates/${id}`;
const attDayStart = () => Timestamp.fromMillis(Date.now() - 86400000);
const attDayEnd = () => Timestamp.fromMillis(Date.now() + 86400000);
const notifList = (db, du) => getDocs(query(collection(db, 'notifications'), where('delegateUid', '==', du), limit(30)));
const notifListAcs = (db) => getDocs(query(
  collection(db, 'notifications'),
  where('companyId', '==', CO),
  where('delegateUid', '==', 'all_company_supervisors'),
  limit(30),
));
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
  ['APP-S', 'supervisor delegate_requests where receiptCode (try/catch)', e => getDocs(query(collection(staff(e,'sup'), 'delegate_requests'), where('receiptCode','==','RC1')))],
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
  ['APP-S', 'branches_marketing attendance org + branch + ts range + limit 2000 (exact main shape)', e => getDocs(query(collection(staff(e,'bm'), 'attendance_logs'), where('organizationId','==',ORG), where('branchName','in',['B1']), where('timestamp','>=',Timestamp.fromMillis(Date.now()-86400000)), where('timestamp','<',Timestamp.fromMillis(Date.now()+86400000)), limit(2000)))],
  ['APP-S', 'branches_marketing create root branch', e => addDoc(collection(staff(e,'bm'), 'branches'), { branchName: 'B2', organizationUID: ORG, organizationId: ORG, latitude: 30, longitude: 31 })],
  ['APP-S', 'tech support list delegate_requests pending', e => getDocs(query(collection(staff(e,'ts'), 'delegate_requests'), where('status','==','pending')))],
  ['APP-S', 'tech support approve request (update status approved)', e => updateDoc(doc(staff(e,'ts'), 'delegate_requests/req1'), { status: 'approved', reviewedBy: 'ts', reviewedAt: new Date().toISOString() })],
  ['APP-S', 'super-admin approve request (update status approved, main step 1)', e => updateDoc(doc(staff(e,'sa'), 'delegate_requests/req1'), { status: 'approved', reviewedBy: 'sa', reviewedAt: new Date().toISOString() })],
  ['APP-S', 'super-admin provision delegate set(merge) status active (main step 2c, unbatched)', e => setDoc(doc(staff(e,'sa'), `organizations/${ORG}/companies/${CO}/delegates/newdlg`), { uid: 'newdlg', name: 'N', status: 'active', organizationUID: ORG, companyUID: CO, phoneNumber: '01000000099', nationalityID: '29901010100099', registeredVia: 'mobile_app' }, { merge: true })],
  ['APP-S', 'tech support provision delegate set(merge) status active (main step 2c, unbatched)', e => setDoc(doc(staff(e,'ts'), `organizations/${ORG}/companies/${CO}/delegates/newdlg`), { uid: 'newdlg', name: 'N', status: 'active', organizationUID: ORG, companyUID: CO, phoneNumber: '01000000099', nationalityID: '29901010100099', registeredVia: 'mobile_app' }, { merge: true })],
  ['APP-S', 'super-admin users list all (collections screen)', e => getDocs(collection(staff(e,'sa'), 'users'))],
  ['APP-S', 'any staff users list all (private label perms: users get())', e => getDocs(collection(staff(e,'mkt'), 'users'))],
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
  ...[
    ['ts', 'technicalSupport'], ['oa', 'organizationAdmin'], ['ca', 'company-admin'],
    ['sup', 'supervisor'], ['hr', 'hr'], ['acc', 'accountant'],
    ['mkt', 'marketing'], ['mp', 'marketing_promotion'], ['bm', 'branchesMarketingManager'],
  ].flatMap(([uid, alias]) => [
    ['NOTIF-READ', `${uid} list bell: delegateUid==all (limit 30)`, e => notifList(staff(e, uid), 'all')],
    ['NOTIF-READ', `${uid} list bell: delegateUid==${alias} (limit 30)`, e => notifList(staff(e, uid), alias)],
    ['NOTIF-READ', `${uid} list bell: delegateUid==company_${CO} (limit 30)`, e => notifList(staff(e, uid), `company_${CO}`)],
    ['NOTIF-READ', `${uid} list bell: companyId+all_company_supervisors (limit 30)`, e => notifListAcs(staff(e, uid))],
    ['NOTIF-READ', `${uid} list bell: delegateUid==hr (limit 30)`, e => notifList(staff(e, uid), 'hr')],
    ['NOTIF-READ', `${uid} list bell: delegateUid==delegates_${CO} (limit 30)`, e => notifList(staff(e, uid), `delegates_${CO}`)],
  ]),
  ['NOTIF-READ', 'delegate list bell: delegateUid==all (limit 30)', e => notifList(delegate(e), 'all')],
  ['NOTIF-READ', 'delegate list bell: delegateUid==delegates_${CO} (limit 30)', e => notifList(delegate(e), `delegates_${CO}`)],
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
    try { await fn(env); res = 'ALLOW'; } catch (e) {
      res = 'DENY';
      (globalThis.MSG ||= {})[label + '|' + name] = String(e.message).replace(/\s+/g, ' ').slice(0, 600);
      if (!String(e.code || e.message).includes('permission')) res = 'ERR:' + String(e.code || e.message).slice(0, 80);
    }
    out.push(res);
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
  await live.cleanup();
  await cand.cleanup();
  const rows = cases.map((c, i) => ({
    area: c[0],
    name: c[1],
    live: rl[i],
    cand: rd[i],
    regression: rl[i] === 'ALLOW' && rd[i] !== 'ALLOW',
    deliberate: DELIBERATE_FIRESTORE_REGRESSIONS.has(c[1]),
    candMsg: (globalThis.MSG || {})['cand|' + c[1]],
  }));
  const unexpected = rows.filter(r => r.regression && !r.deliberate);
  const deliberate = rows.filter(r => r.regression && r.deliberate);
  return { rows, total: rows.length, deliberate, unexpected, exprLimit: unexpected.filter(r => String(r.candMsg || '').includes('limit exceeded')) };
}