import path from 'path';
import { fileURLToPath } from 'url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import fs from 'fs';
import { doc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const FS_PORT = Number(process.env.LOCAL_CI_FIRESTORE_PORT || 8080);
const ST_PORT = Number(process.env.LOCAL_CI_STORAGE_PORT || 9199);
const LIVE_RULES = path.join(ROOT, 'test/rules/ta60/live.storage.rules');
const CAND_RULES = process.env.SCAND || path.join(ROOT, 'storage.rules');
const FS_RULES = path.join(ROOT, 'firestore.rules');

const ORG = 'orgA', CO = 'coA';
const img = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const meta = { contentType: 'image/jpeg' };

async function mkEnv(storageRulesFile, projectId) {
  return initializeTestEnvironment({
    projectId,
    firestore: { rules: fs.readFileSync(FS_RULES, 'utf8'), host: '127.0.0.1', port: FS_PORT },
    storage: { rules: fs.readFileSync(storageRulesFile, 'utf8'), host: '127.0.0.1', port: ST_PORT },
  });
}

async function seed(env) {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const U = {
      sup: { role: 'supervisor', organizationUID: ORG, companyUID: CO },
      ca: { role: 'company-admin', organizationUID: ORG, companyUID: CO },
      oaEmpty: { role: 'organization-admin', organizationUID: ORG, companyUID: '' },
      oaWeb: { role: 'organization-admin', organizationId: ORG, companyId: null },
      hr: { role: 'hr', organizationUID: ORG, companyUID: CO },
      mkt: { role: 'marketing', organizationUID: ORG, companyUID: '' },
      sa: { role: 'super-admin' },
      ts: { role: 'technical_support' },
    };
    for (const [k, v] of Object.entries(U)) await setDoc(doc(db, 'users', k), { uid: k, ...v });
    await setDoc(doc(db, `organizations/${ORG}`), { name: 'o' });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}`), { name: 'c', organizationUID: ORG });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/delegates/dlg1`), { uid: 'dlg1', status: 'active', companyUID: CO, organizationUID: ORG });
    await setDoc(doc(db, 'users/dlg1'), { uid: 'dlg1', role: 'delegate', organizationUID: ORG, companyUID: CO, status: 'approved' });
    await setDoc(doc(db, `organizations/${ORG}/companies/${CO}/requests/webReq1`), { uid: 'webReq1', companyUID: CO, organizationUID: ORG, status: 'pending', actionType: 'create' });
    await setDoc(doc(db, 'delegate_requests/oldReq'), { companyUID: CO, organizationUID: ORG, supervisorUid: 'sup', status: 'pending' });
    const s = c.storage();
    await uploadBytes(ref(s, `organizations/${ORG}/companies/${CO}/documents/taxCard/t.pdf`), img, meta);
    await uploadBytes(ref(s, `organizations/${ORG}/companies/${CO}/delegates/dlg1/personalPhoto/p.jpg`), img, meta);
    await uploadBytes(ref(s, 'delegate_documents/dlg1/profile.jpg'), img, meta);
    await uploadBytes(ref(s, 'penalties/evidence/p1/e.jpg'), img, meta);
    await setDoc(doc(db, 'storage_upload_intents/dlg1'), { companyUID: CO, createdBy: 'seed' });
    await setDoc(doc(db, 'storage_upload_intents/newReq1'), { companyUID: CO, createdBy: 'sup' });
    await setDoc(doc(db, 'storage_upload_intents/oldReq'), { companyUID: CO, createdBy: 'sup' });
    await setDoc(doc(db, 'storage_upload_intents/webReq1'), { companyUID: CO, createdBy: 'ca' });
    await setDoc(doc(db, 'storage_upload_intents/webNew'), { companyUID: CO, createdBy: 'ca' });
  });
}

const st = (env, uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).storage();
const dl = (env) => env.authenticatedContext('dlg1', { role: 'delegate', delegateId: 'dlg1', orgId: ORG, companyId: CO, firebase: { sign_in_provider: 'custom' } }).storage();
const up = (s, p) => uploadBytes(ref(s, p), img, meta);

const cases = [
  ['APP', 'supervisor registration upload delegate_documents/{newReqId}/profile.jpg (request doc not yet created)', e => up(st(e, 'sup'), 'delegate_documents/newReq1/profile.jpg')],
  ['APP', 'supervisor registration upload national_id_front.jpg', e => up(st(e, 'sup'), 'delegate_documents/newReq1/national_id_front.jpg')],
  ['APP', 'supervisor registration upload delegate_subscription_receipts/{newReqId}/receipt.jpg', e => up(st(e, 'sup'), 'delegate_subscription_receipts/newReq1/receipt.jpg')],
  ['APP', 'supervisor upload delegate_documents/{existing delegate_requests id}', e => up(st(e, 'sup'), 'delegate_documents/oldReq/profile.jpg')],
  ['APP', 'tech-support read delegate_documents/dlg1', e => getBytes(ref(st(e, 'ts'), 'delegate_documents/dlg1/profile.jpg'))],
  ['APP', 'supervisor read delegate_documents/dlg1 (same company, no intent)', e => getBytes(ref(st(e, 'sup'), 'delegate_documents/dlg1/profile.jpg'))],
  ['APP', 'delegate upload own delegate_documents/dlg1/personalPhoto_ts.jpg', e => up(dl(e), 'delegate_documents/dlg1/personalPhoto_1.jpg')],
  ['APP', 'supervisor penalties/evidence/{id}/ts_x.jpg upload', e => up(st(e, 'sup'), 'penalties/evidence/p9/1_x.jpg')],
  ['APP', 'supervisor penalties/evidence/temp upload', e => up(st(e, 'sup'), 'penalties/evidence/temp/1_x.jpg')],
  ['APP', 'hr leave_attachments/{co}/{dlg}/x upload', e => up(st(e, 'hr'), `leave_attachments/${CO}/dlg1/x.jpg`)],
  ['APP', 'delegate photo permission organizations/{o}/companies/{c}/permissions/p1/photo_ts.jpg', e => up(dl(e), `organizations/${ORG}/companies/${CO}/permissions/p1/photo_1.jpg`)],
  ['APP', 'marketing private_label organizations/{o}/private_label/2026-11/x.jpg', e => up(st(e, 'mkt'), `organizations/${ORG}/private_label/2026-11/x_before.jpg`)],
  ['APP', 'delegate feedback_screenshots/feedback_ts.jpg (main filename)', e => up(dl(e), 'feedback_screenshots/feedback_1.jpg')],
  ['WEB', 'company-admin staging/requests/{webReq}/personalPhoto/x.jpg upload (nested request)', e => up(st(e, 'ca'), 'staging/requests/webReq1/personalPhoto/x.jpg')],
  ['WEB', 'company-admin staging/requests/{newUid}/x upload (request not yet written)', e => up(st(e, 'ca'), 'staging/requests/webNew/personalPhoto/x.jpg')],
  ['WEB', 'company-admin company documents upload', e => up(st(e, 'ca'), `organizations/${ORG}/companies/${CO}/documents/taxCard/n.pdf`)],
  ['WEB', 'org-admin (companyUID empty) read company documents', e => getBytes(ref(st(e, 'oaEmpty'), `organizations/${ORG}/companies/${CO}/documents/taxCard/t.pdf`))],
  ['WEB', 'org-admin (web-created doc: organizationId only) read company documents', e => getBytes(ref(st(e, 'oaWeb'), `organizations/${ORG}/companies/${CO}/documents/taxCard/t.pdf`))],
  ['WEB', 'org-admin (companyUID empty) upload company documents', e => up(st(e, 'oaEmpty'), `organizations/${ORG}/companies/${CO}/documents/taxCard/o.pdf`)],
  ['WEB', 'org-admin (companyUID empty) read delegate ID doc', e => getBytes(ref(st(e, 'oaEmpty'), `organizations/${ORG}/companies/${CO}/delegates/dlg1/personalPhoto/p.jpg`))],
  ['WEB', 'company-admin read delegate ID doc', e => getBytes(ref(st(e, 'ca'), `organizations/${ORG}/companies/${CO}/delegates/dlg1/personalPhoto/p.jpg`))],
  ['WEB', 'super-admin guide-videos upload', e => uploadBytes(ref(st(e, 'sa'), 'guide-videos/1_v.mp4'), img, { contentType: 'video/mp4' })],
];

async function runOne(env, fn) {
  await seed(env);
  try {
    await fn(env);
    return ['ALLOW', ''];
  } catch (e) {
    return [
      String(e.code || '').includes('unauthorized') ? 'DENY' : 'ERR',
      String(e.message).replace(/\s+/g, ' ').slice(0, 200),
    ];
  }
}

export async function runStorageCompatHarness() {
  // Two emulator projects in parallel so live vs candidate storage rules both load
  // (sequential re-init on one projectId left candidate on stale live rules — false green).
  const liveEnv = await mkEnv(LIVE_RULES, 'demo-ta60-st-live');
  const candEnv = await mkEnv(CAND_RULES, 'demo-ta60-st-cand');
  const live = [];
  const cand = [];
  for (const [, , f] of cases) {
    live.push(await runOne(liveEnv, f));
    cand.push(await runOne(candEnv, f));
  }
  await liveEnv.cleanup();
  await candEnv.cleanup();
  const rows = cases.map((c, i) => ({
    area: c[0],
    name: c[1],
    live: live[i][0],
    cand: cand[i][0],
    candMsg: cand[i][1],
    regression: live[i][0] === 'ALLOW' && cand[i][0] !== 'ALLOW',
  }));
  const unexpected = rows.filter(r => r.regression);
  return { rows, total: rows.length, unexpected };
}