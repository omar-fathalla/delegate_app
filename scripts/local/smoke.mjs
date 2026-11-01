// End-to-end smoke test against the RUNNING local emulators (scripts/local_rules_test.sh).
// Logs in exactly like the app (staffPhoneLookup -> email/password,
// delegateLoginV2 -> custom token) and runs the app's scoped delegate queries.
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, signInWithEmailAndPassword, signInWithCustomToken, signInAnonymously, signOut } from 'firebase/auth';
import { getFirestore, connectFirestoreEmulator, collectionGroup, collection, query, where, getDocs, doc, getDoc } from 'firebase/firestore';
import { getFunctions, connectFunctionsEmulator, httpsCallable } from 'firebase/functions';

const PASSWORD = 'Test@12345';
let pass = 0, fail = 0;
const check = async (label, fn, expectOk = true) => {
  try { const r = await fn(); if (expectOk) { pass++; console.log(`  ✔ ${label}${r !== undefined ? ' → ' + r : ''}`); } else { fail++; console.log(`  ✖ ${label} (expected DENIED, got allowed)`); } }
  catch (e) { if (!expectOk) { pass++; console.log(`  ✔ ${label} → denied as expected`); } else { fail++; console.log(`  ✖ ${label}: ${e.code || e.message}`); } }
};
function client(name) {
  const app = initializeApp({ projectId: 'demo-tashil-local', apiKey: 'fake-api-key', authDomain: 'localhost' }, name);
  const auth = getAuth(app); connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const db = getFirestore(app); connectFirestoreEmulator(db, '127.0.0.1', 8080);
  const fns = getFunctions(app, 'us-central1'); connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  return { app, auth, db, fns };
}
const n = (snap) => snap.size;

const staff = [
  ['01090000001', 'super-admin', null],
  ['01090000003', 'organization-admin', ['organizationUID', 'org_test_a']],
  ['01090000004', 'marketing', ['organizationUID', 'org_test_a']],
  ['01090000007', 'accountant', ['organizationUID', 'org_test_a']],
  ['01090000008', 'company-admin', ['organizationUID', 'org_test_a']],
  ['01090000009', 'company-admin (no company)', ['organizationUID', 'org_test_a']],
  ['01090000010', 'company_supervisor', ['organizationUID', 'org_test_a']],
  ['01090000011', 'hr', ['organizationUID', 'org_test_a']],
  ['01090000012', 'organization-admin org B', ['organizationUID', 'org_test_b']],
];
for (const [phone, label, scope] of staff) {
  console.log(`\n[staff] ${label} ${phone}`);
  const c = client('s' + phone);
  await check('staffPhoneLookup callable', async () => {
    const r = await httpsCallable(c.fns, 'staffPhoneLookup')({ phone });
    await signInWithEmailAndPassword(c.auth, r.data.email, PASSWORD);
    return r.data.role;
  });
  const cg = collectionGroup(c.db, 'delegates');
  const scoped = scope ? query(cg, where(scope[0], '==', scope[1])) : cg;
  await check('scoped delegates list (DelegateQueryScope)', async () => n(await getDocs(scoped)) + ' docs');
  await check('scoped + phone lookup', async () => n(await getDocs(query(scoped, where('phoneNumber', '==', '01080000001')))) + ' docs');
  await check('company docs', async () => n(await getDocs(collectionGroup(c.db, 'companies'))) + ' docs');
  if (scope) await check('unfiltered collectionGroup(delegates)', () => getDocs(cg), false);
  if (scope) await check('other org delegates', () => getDocs(query(cg, where('organizationUID', '==', scope[1] === 'org_test_a' ? 'org_test_b' : 'org_test_a'))), false);
  await deleteApp(c.app);
}

const delegates = [['01080000001', '29901010100011', 'co_test_a1'], ['01080000004', '29901010100044', 'co_test_b1']];
for (const [phone, nid, co] of delegates) {
  console.log(`\n[delegate] ${phone} (${co})`);
  const c = client('d' + phone);
  let ids = [];
  await check('delegateLoginV2 callable + custom token', async () => {
    const r = await httpsCallable(c.fns, 'delegateLoginV2')({ phone, nationalId: nid, deviceId: 'local-smoke-device-' + phone });
    ids = r.data.delegateIds;
    await signInWithCustomToken(c.auth, r.data.token);
    return ids.join(',');
  });
  const variants = [phone, phone.slice(1), '20' + phone.slice(1), '+20' + phone.slice(1), '0020' + phone.slice(1), '+2' + phone, '002' + phone];
  const cg = collectionGroup(c.db, 'delegates');
  await check('app login query: phoneNumber in variants', async () => n(await getDocs(query(cg, where('phoneNumber', 'in', variants)))) + ' docs');
  await check('own company (companyUID filter)', async () => n(await getDocs(query(cg, where('companyUID', '==', co)))) + ' docs');
  await check('own uid', async () => n(await getDocs(query(cg, where('uid', '==', ids[0])))) + ' docs');
  await check('other company', () => getDocs(query(cg, where('companyUID', '==', co === 'co_test_a1' ? 'co_test_b1' : 'co_test_a1'))), false);
  await deleteApp(c.app);
}

console.log('\n[anonymous] (old app <= 1.14.1 behaviour)');
{
  const c = client('anon');
  await signInAnonymously(c.auth);
  await check('anonymous delegates by phone', () => getDocs(query(collectionGroup(c.db, 'delegates'), where('phoneNumber', '==', '01080000001'))), false);
  await deleteApp(c.app);
}
console.log(`\nSMOKE: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
