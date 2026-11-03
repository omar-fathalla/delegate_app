// Phase 1b Firestore rules tests (scoped delegate reads). Emulator only.
// Mirrors the query shapes the app sends after the DelegateQueryScope change
// and the Angular dashboard queries.
import { test, before, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, collectionGroup,
  query, where, getDocs, limit, increment,
} from 'firebase/firestore';

const RULES = process.env.RULES_FILE_1B || '../firestore.rules.phase1b';
let env;
const A = 'orgA', B = 'orgB';
const cA1 = 'cA1', cA2 = 'cA2', cB1 = 'cB1';
const dPath = (o, c, d) => `organizations/${o}/companies/${c}/delegates/${d}`;
const variants = (p) => [p, p.slice(1), '20' + p.slice(1), '+20' + p.slice(1), '0020' + p.slice(1), '+2' + p, '002' + p];
const PHONE_A1 = '01000000001';

const staff = {
  super: { role: 'super-admin' },
  tech: { role: 'technical_support', organizationUID: A },
  orgAdmin: { role: 'organization-admin', organizationUID: A },
  marketing: { role: 'marketing', organizationUID: A },
  mprom: { role: 'marketing_promotion', organizationUID: A },
  branchesMkt: { role: 'branches_marketing', organizationUID: A },
  accountant: { role: 'accountant', organizationUID: A },
  compAdmin: { role: 'company-admin', organizationUID: A, companyUID: cA1 },
  compAdminNoOrg: { role: 'company-admin', organizationUID: '', companyUID: cA1 },
  compAdminNoCo: { role: 'company-admin', organizationUID: A, companyUID: '' },
  compSup: { role: 'company_supervisor', organizationUID: A, companyUID: cA1 },
  hr: { role: 'hr', organizationUID: A, companyUID: cA1 },
  noRole: { photoURL: 'x' },
};

function ctx(name) {
  if (name === 'unauth') return env.unauthenticatedContext().firestore();
  if (name === 'anon') return env.authenticatedContext('anon1', { firebase: { sign_in_provider: 'anonymous' } }).firestore();
  if (name === 'delegate') return env.authenticatedContext('dlgA1', {
    role: 'delegate', orgId: A, companyId: cA1, delegateIds: ['dA1'], phones: variants(PHONE_A1),
    firebase: { sign_in_provider: 'custom' },
  }).firestore();
  if (name === 'delegateMulti') return env.authenticatedContext('dlgM', {
    role: 'delegate', orgId: A, companyId: cA1, companyIds: [cA1, cB1], orgIds: [A, B], delegateIds: ['dA1', 'dB1'],
    firebase: { sign_in_provider: 'custom' },
  }).firestore();
  return env.authenticatedContext(name, { firebase: { sign_in_provider: 'password' } }).firestore();
}
const cg = (db, ...w) => getDocs(query(collectionGroup(db, 'delegates'), ...w));

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules-phase1b',
    firestore: { rules: readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8089 },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    for (const [uid, data] of Object.entries(staff)) await setDoc(doc(db, 'users', uid), data);
    for (const o of [A, B]) await setDoc(doc(db, 'organizations', o), { name: o, admins: 1 });
    for (const [o, c2] of [[A, cA1], [A, cA2], [B, cB1]]) await setDoc(doc(db, `organizations/${o}/companies/${c2}`), { name: c2, admins: 1 });
    const dl = [[A, cA1, 'dA1', PHONE_A1], [A, cA2, 'dA2', '01000000002'], [B, cB1, 'dB1', '01000000003']];
    for (const [o, c2, d, ph] of dl) await setDoc(doc(db, dPath(o, c2, d)), {
      organizationUID: o, companyUID: c2, phoneNumber: ph, name: d, uid: d, nationalId: 'N' + d, receiptCode: 'R' + d,
    });
  });
});
after(async () => { await env.cleanup(); });

// ---------- closed in 1b ----------
test('unauth / anonymous / no-role: no delegate reads at all', async () => {
  for (const who of ['unauth', 'anon', 'noRole']) {
    const db = ctx(who);
    await assertFails(getDoc(doc(db, dPath(A, cA1, 'dA1'))));
    await assertFails(cg(db, where('phoneNumber', '==', PHONE_A1)));
    await assertFails(getDocs(collection(db, `organizations/${A}/companies/${cA1}/delegates`)));
  }
});

test('anonymous: delegate updates closed (were legacy-allowed in phase 1)', async () => {
  await assertFails(updateDoc(doc(ctx('anon'), dPath(B, cB1, 'dB1')), { lastSeen: 1 }));
});

test('unfiltered collectionGroup(delegates) denied for every non-global role', async () => {
  for (const who of ['orgAdmin', 'marketing', 'compAdmin', 'compSup', 'hr', 'delegate']) {
    await assertFails(cg(ctx(who)));
    await assertFails(cg(ctx(who), where('phoneNumber', '==', '01000000003')));
  }
});

// ---------- global ----------
for (const who of ['super', 'tech']) {
  test(`${who}: global reads unchanged (unfiltered CG, paging, any company)`, async () => {
    const db = ctx(who);
    await assertSucceeds(cg(db));
    await assertSucceeds(cg(db, limit(50)));
    await assertSucceeds(getDoc(doc(db, dPath(B, cB1, 'dB1'))));
  });
}

// ---------- org staff ----------
for (const who of ['orgAdmin', 'marketing', 'mprom', 'branchesMkt', 'accountant']) {
  test(`${who}: own org via organizationUID filter, other org denied`, async () => {
    const db = ctx(who);
    await assertSucceeds(cg(db, where('organizationUID', '==', A)));
    await assertSucceeds(cg(db, where('organizationUID', '==', A), where('phoneNumber', '==', PHONE_A1)));
    await assertSucceeds(cg(db, where('organizationUID', '==', A), where('uid', '==', 'dA2')));
    await assertSucceeds(getDoc(doc(db, dPath(A, cA2, 'dA2'))));
    await assertSucceeds(getDocs(collection(db, `organizations/${A}/companies/${cA2}/delegates`)));
    await assertFails(cg(db, where('organizationUID', '==', B)));
    await assertFails(getDoc(doc(db, dPath(B, cB1, 'dB1'))));
    await assertFails(getDocs(collection(db, `organizations/${B}/companies/${cB1}/delegates`)));
  });
}

// ---------- company staff ----------
for (const who of ['compAdmin', 'compSup', 'hr']) {
  test(`${who}: company filter + own-org filter work; other org denied`, async () => {
    const db = ctx(who);
    await assertSucceeds(cg(db, where('companyUID', '==', cA1)));
    await assertSucceeds(cg(db, where('organizationUID', '==', A), where('uid', '==', 'dA1')));
    await assertSucceeds(cg(db, where('organizationUID', '==', A), where('receiptCode', '==', 'RdA1'), limit(1)));
    await assertSucceeds(getDocs(collection(db, `organizations/${A}/companies/${cA1}/delegates`)));
    await assertSucceeds(getDoc(doc(db, dPath(A, cA1, 'dA1'))));
    await assertFails(cg(db, where('companyUID', '==', cB1)));
    await assertFails(getDoc(doc(db, dPath(B, cB1, 'dB1'))));
  });
}

test('company-admin without org: company filter only', async () => {
  const db = ctx('compAdminNoOrg');
  await assertSucceeds(cg(db, where('companyUID', '==', cA1)));
  await assertFails(cg(db, where('companyUID', '==', cA2)));
  await assertFails(getDoc(doc(db, dPath(A, cA2, 'dA2'))));
});

test('company-admin without companyUID: org filter (legacy 6 accounts)', async () => {
  const db = ctx('compAdminNoCo');
  await assertSucceeds(cg(db, where('organizationUID', '==', A)));
  await assertSucceeds(getDocs(collection(db, `organizations/${A}/companies/${cA2}/delegates`)));
  await assertFails(cg(db, where('organizationUID', '==', B)));
});

// ---------- delegates (custom-claims session) ----------
test('delegate: login lookup by phone variants (claims.phones), own docs, own company', async () => {
  const db = ctx('delegate');
  await assertSucceeds(cg(db, where('phoneNumber', 'in', variants(PHONE_A1))));
  await assertSucceeds(cg(db, where('phoneNumber', '==', PHONE_A1)));
  await assertSucceeds(cg(db, where('uid', '==', 'dA1')));
  await assertSucceeds(cg(db, where('companyUID', '==', cA1)));
  await assertSucceeds(getDoc(doc(db, dPath(A, cA1, 'dA1'))));
  await assertSucceeds(getDocs(query(collection(db, `organizations/${A}/companies/${cA1}/delegates`), where('position', 'in', ['supervisor']))));
  await assertFails(cg(db, where('phoneNumber', '==', '01000000003')));
  await assertFails(cg(db, where('companyUID', '==', cB1)));
  await assertFails(getDoc(doc(db, dPath(A, cA2, 'dA2'))));
  await assertSucceeds(updateDoc(doc(db, dPath(A, cA1, 'dA1')), { fcmToken: 't' }));
  await assertFails(updateDoc(doc(db, dPath(A, cA1, 'dA1')), { companyUID: cB1 }));
});

test('delegate in 2 companies: companyUID in [...] works for both', async () => {
  const db = ctx('delegateMulti');
  await assertSucceeds(cg(db, where('companyUID', 'in', [cA1, cB1])));
  await assertSucceeds(getDoc(doc(db, dPath(B, cB1, 'dB1'))));
  await assertFails(cg(db, where('companyUID', '==', cA2)));
});

// ---------- writes from phase 1 still hold ----------
test('phase 1 write scoping unchanged', async () => {
  await assertSucceeds(updateDoc(doc(ctx('compAdmin'), dPath(A, cA1, 'dA1')), { note: 'x' }));
  await assertFails(updateDoc(doc(ctx('compAdmin'), dPath(A, cA2, 'dA2')), { note: 'x' }));
  await assertSucceeds(updateDoc(doc(ctx('marketing'), dPath(A, cA2, 'dA2')), { note: 'x' }));
  await assertFails(updateDoc(doc(ctx('marketing'), dPath(B, cB1, 'dB1')), { note: 'x' }));
  await assertSucceeds(setDoc(doc(ctx('hr'), dPath(A, cA1, 'n1')), { organizationUID: A, companyUID: cA1 }));
  await assertSucceeds(deleteDoc(doc(ctx('hr'), dPath(A, cA1, 'n1'))));
  await assertSucceeds(updateDoc(doc(ctx('newU'), `organizations/${A}/companies/${cA2}`), { admins: increment(1) }));
});

// ---------- Angular dashboards ----------
test('Angular company-admin + org-admin queries', async () => {
  await assertSucceeds(getDocs(collection(ctx('compAdmin'), `organizations/${A}/companies/${cA1}/delegates`)));
  await assertSucceeds(cg(ctx('compAdmin'), where('companyUID', '==', cA1)));
  await assertSucceeds(cg(ctx('orgAdmin'), where('organizationUID', '==', A)));
  await assertSucceeds(getDocs(collection(ctx('orgAdmin'), `organizations/${A}/companies`)));
});
