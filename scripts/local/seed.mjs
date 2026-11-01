// Seeds the LOCAL Firebase emulators with fake, non-real test data.
// Refuses to run unless both emulator hosts are set and the project is demo-*.
import admin from 'firebase-admin';

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-tashil-local';
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST || !PROJECT.startsWith('demo-')) {
  console.error('Refusing to seed: emulator hosts not set or project is not demo-*');
  process.exit(1);
}
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const auth = admin.auth();

const PASSWORD = 'Test@12345'; // emulator-only fake password
const ORG_A = 'org_test_a', ORG_B = 'org_test_b';
const CO_A1 = 'co_test_a1', CO_A2 = 'co_test_a2', CO_B1 = 'co_test_b1';

const staff = [
  ['super',       'super-admin',         '01090000001', '',    ''],
  ['tech',        'technical_support',   '01090000002', ORG_A, ''],
  ['orgadmin',    'organization-admin',  '01090000003', ORG_A, ''],
  ['marketing',   'marketing',           '01090000004', ORG_A, ''],
  ['mprom',       'marketing_promotion', '01090000005', ORG_A, ''],
  ['branchesmkt', 'branches_marketing',  '01090000006', ORG_A, ''],
  ['accountant',  'accountant',          '01090000007', ORG_A, ''],
  ['compadmin',   'company-admin',       '01090000008', ORG_A, CO_A1],
  ['compadminnoco','company-admin',      '01090000009', ORG_A, ''],
  ['compsup',     'company_supervisor',  '01090000010', ORG_A, CO_A1],
  ['hr',          'hr',                  '01090000011', ORG_A, CO_A1],
  ['orgadminb',   'organization-admin',  '01090000012', ORG_B, ''],
];

const delegates = [
  ['dlg_a1_1', ORG_A, CO_A1, '01080000001', '29901010100011', 'مندوب تجريبي A1-1', 'delegate'],
  ['dlg_a1_2', ORG_A, CO_A1, '01080000002', '29901010100022', 'مشرف تجريبي A1', 'supervisor'],
  ['dlg_a2_1', ORG_A, CO_A2, '01080000003', '29901010100033', 'مندوب تجريبي A2-1', 'delegate'],
  ['dlg_b1_1', ORG_B, CO_B1, '01080000004', '29901010100044', 'مندوب تجريبي B1-1', 'delegate'],
];

async function upsertUser(uid, email, phone, name) {
  try { await auth.deleteUser(uid); } catch {}
  await auth.createUser({ uid, email, password: PASSWORD, displayName: name, phoneNumber: '+2' + phone });
}

const now = admin.firestore.FieldValue.serverTimestamp();
for (const [o, name] of [[ORG_A, 'منظمة تجريبية A'], [ORG_B, 'منظمة تجريبية B']]) {
  await db.doc(`organizations/${o}`).set({ name, organizationName: name, admins: 1, isTestData: true, createdAt: now });
}
for (const [o, c, name] of [[ORG_A, CO_A1, 'شركة تجريبية A1'], [ORG_A, CO_A2, 'شركة تجريبية A2'], [ORG_B, CO_B1, 'شركة تجريبية B1']]) {
  await db.doc(`organizations/${o}/companies/${c}`).set({
    name, companyName: name, organizationUID: o, admins: 1, isTestData: true, createdAt: now,
  });
  await db.doc(`organizations/${o}/branches/br_${c}`).set({ name: 'فرع ' + name, companyUID: c, organizationUID: o, isTestData: true });
}

const out = [];
for (const [key, role, phone, org, co] of staff) {
  const uid = `test_${key}`;
  const email = `${key}@tashil-local.test`;
  await upsertUser(uid, email, phone, `${role} (test)`);
  await db.doc(`users/${uid}`).set({
    uid, email, role, phoneNumber: phone, name: `${role} تجريبي`, fullName: `${role} تجريبي`,
    organizationUID: org, companyUID: co, isTestAccount: true, createdAt: now,
  });
  out.push({ type: 'staff', role, phone, email, password: PASSWORD, org, company: co || '-' });
}

for (const [id, o, c, phone, nid, name, position] of delegates) {
  await db.doc(`organizations/${o}/companies/${c}/delegates/${id}`).set({
    uid: id, fullName: name, name, phoneNumber: phone, nationalityID: nid, nationalId: nid,
    organizationUID: o, companyUID: c, position, role: 'delegate', status: 'active',
    isTestData: true, createdAt: now,
  });
  out.push({ type: 'delegate', role: position, phone, nationalId: nid, org: o, company: c });
}

console.log('\n=== Seeded emulator accounts (FAKE, emulator only) ===');
console.table(out.map(({ type, role, phone, email, password, nationalId, org, company }) =>
  ({ type, role, phone, login: email ? `password: ${password}` : `nationalId: ${nationalId}`, org, company })));
process.exit(0);
