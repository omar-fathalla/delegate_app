// Phase 1 Firestore rules tests. Runs only against the local emulator.
import { test, before, after } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, collectionGroup,
  query, where, getDocs, increment,
} from 'firebase/firestore';

const RULES = process.env.RULES_FILE || '../firestore.rules.phase1';
let env;

const A = 'orgA', B = 'orgB';
const cA1 = 'cA1', cA2 = 'cA2', cB1 = 'cB1';
const dPath = (o, c, d) => `organizations/${o}/companies/${c}/delegates/${d}`;

const staff = {
  super:      { role: 'super-admin' },
  tech:       { role: 'technical_support', organizationUID: A },
  orgAdmin:   { role: 'organization-admin', organizationUID: A },
  marketing:  { role: 'marketing', organizationUID: A },
  mprom:      { role: 'marketing_promotion', organizationUID: A },
  branchesMkt:{ role: 'branches_marketing', organizationUID: A },
  accountant: { role: 'accountant', organizationUID: A },
  compAdmin:  { role: 'company-admin', organizationUID: A, companyUID: cA1 },
  compAdminNoCo: { role: 'company-admin', organizationUID: A, companyUID: '' },
  compSup:    { role: 'company_supervisor', organizationUID: A, companyUID: cA1 },
  hr:         { role: 'hr', organizationUID: A, companyUID: cA1 },
  noRole:     { photoURL: 'x' },
};

const as = {};
function ctx(name) {
  if (name === 'unauth') return env.unauthenticatedContext().firestore();
  if (name === 'anon') return env.authenticatedContext('anon1', { firebase: { sign_in_provider: 'anonymous' } }).firestore();
  if (name === 'delegate') return env.authenticatedContext('dlgA1', {
    role: 'delegate', orgId: A, companyId: cA1, delegateIds: ['dA1'],
    firebase: { sign_in_provider: 'custom' },
  }).firestore();
  if (name === 'newUser') return env.authenticatedContext('newUser1', { firebase: { sign_in_provider: 'password' } }).firestore();
  return env.authenticatedContext(name, { firebase: { sign_in_provider: 'password' } }).firestore();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules-phase1',
    firestore: { rules: readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8089 },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    for (const [uid, data] of Object.entries(staff)) await setDoc(doc(db, 'users', uid), data);
    for (const o of [A, B]) await setDoc(doc(db, 'organizations', o), { name: o, admins: 1 });
    for (const [o, c2] of [[A, cA1], [A, cA2], [B, cB1]]) {
      await setDoc(doc(db, `organizations/${o}/companies/${c2}`), { name: c2, admins: 1 });
      await setDoc(doc(db, `organizations/${o}/branches/br-${c2}`), { name: 'b' });
    }
    const dl = [[A, cA1, 'dA1'], [A, cA2, 'dA2'], [B, cB1, 'dB1']];
    for (const [o, c2, d] of dl) await setDoc(doc(db, dPath(o, c2, d)), {
      organizationUID: o, companyUID: c2, phoneNumber: `010${d}`, name: d, uid: d,
    });
    await setDoc(doc(db, 'branches/root1'), { organizationUID: A });
    await setDoc(doc(db, 'penalty_rules/r1'), { organizationUID: A });
    await setDoc(doc(db, `organizations/${A}/companies/${cA1}/requests/rq1`), { organizationUID: A, companyUID: cA1 });
  });
});
after(async () => { await env.cleanup(); });

// ---------- unauthenticated: everything that used to be public is closed ----------
test('unauth cannot read company / org / branches / users / penalty_rules / delegates', async () => {
  const db = ctx('unauth');
  await assertFails(getDoc(doc(db, `organizations/${A}/companies/${cA1}`)));
  await assertFails(getDocs(collectionGroup(db, 'companies')));
  await assertFails(getDoc(doc(db, `organizations/${A}`)));
  await assertFails(getDoc(doc(db, `organizations/${A}/branches/br-${cA1}`)));
  await assertFails(getDoc(doc(db, 'branches/root1')));
  await assertFails(getDoc(doc(db, 'users/compAdmin')));
  await assertFails(getDoc(doc(db, 'penalty_rules/r1')));
  await assertFails(getDoc(doc(db, dPath(A, cA1, 'dA1'))));
});

// ---------- reads that must keep working for every signed-in session ----------
for (const who of ['anon', 'delegate', 'compAdmin', 'compSup', 'hr', 'super', 'marketing', 'noRole']) {
  test(`${who}: signed-in reads still work (company, org, branches, penalty rules, delegates by phone)`, async () => {
    const db = ctx(who);
    await assertSucceeds(getDoc(doc(db, `organizations/${A}/companies/${cA1}`)));
    await assertSucceeds(getDoc(doc(db, `organizations/${A}`)));
    await assertSucceeds(getDoc(doc(db, 'branches/root1')));
    await assertSucceeds(getDocs(collection(db, `organizations/${A}/branches`)));
    await assertSucceeds(getDocs(collection(db, 'penalty_rules')));
    await assertSucceeds(getDocs(query(collectionGroup(db, 'delegates'), where('phoneNumber', '==', '010dA1'))));
  });
}

// ---------- delegate writes: cross-company closed ----------
const upd = (db, o, c2, d, data = { note: 'x' }) => updateDoc(doc(db, dPath(o, c2, d)), data);

test('company-admin (company A1): own company delegates yes, other company/org no', async () => {
  const db = ctx('compAdmin');
  await assertSucceeds(upd(db, A, cA1, 'dA1'));
  await assertFails(upd(db, A, cA2, 'dA2'));
  await assertFails(upd(db, B, cB1, 'dB1'));
  await assertSucceeds(setDoc(doc(db, dPath(A, cA1, 'newA1')), { organizationUID: A, companyUID: cA1, name: 'n' }));
  await assertFails(setDoc(doc(db, dPath(B, cB1, 'newB1')), { organizationUID: B, companyUID: cB1, name: 'n' }));
  await assertFails(deleteDoc(doc(db, dPath(A, cA2, 'dA2'))));
  await assertSucceeds(deleteDoc(doc(db, dPath(A, cA1, 'newA1'))));
});

for (const who of ['compSup', 'hr']) {
  test(`${who}: scoped to own company`, async () => {
    const db = ctx(who);
    await assertSucceeds(upd(db, A, cA1, 'dA1'));
    await assertFails(upd(db, A, cA2, 'dA2'));
    await assertFails(upd(db, B, cB1, 'dB1'));
  });
}

test('legacy company-admin without companyUID: falls back to its org, not other orgs', async () => {
  const db = ctx('compAdminNoCo');
  await assertSucceeds(upd(db, A, cA2, 'dA2'));
  await assertFails(upd(db, B, cB1, 'dB1'));
});

for (const who of ['orgAdmin', 'marketing', 'mprom', 'branchesMkt', 'accountant']) {
  test(`${who}: scoped to own org`, async () => {
    const db = ctx(who);
    await assertSucceeds(upd(db, A, cA2, 'dA2'));
    await assertFails(upd(db, B, cB1, 'dB1'));
  });
}

for (const who of ['super', 'tech']) {
  test(`${who}: global`, async () => {
    await assertSucceeds(upd(ctx(who), B, cB1, 'dB1'));
  });
}

test('delegate (delegateLoginV2 claims): own company, cannot move scope, cannot create/delete', async () => {
  const db = ctx('delegate');
  await assertSucceeds(upd(db, A, cA1, 'dA1', { fcmToken: 't' }));
  await assertFails(upd(db, A, cA1, 'dA1', { companyUID: cB1 }));
  await assertFails(upd(db, B, cB1, 'dB1'));
  await assertFails(setDoc(doc(db, dPath(A, cA1, 'x')), { organizationUID: A, companyUID: cA1 }));
  await assertFails(deleteDoc(doc(db, dPath(A, cA1, 'dA1'))));
});

test('anonymous (old app <= 1.14.1): legacy update only, no scope move, no create/delete', async () => {
  const db = ctx('anon');
  await assertSucceeds(upd(db, B, cB1, 'dB1', { lastSeen: 1 }));
  await assertFails(upd(db, B, cB1, 'dB1', { organizationUID: A }));
  await assertFails(setDoc(doc(db, dPath(A, cA1, 'anonNew')), { organizationUID: A, companyUID: cA1 }));
  await assertFails(deleteDoc(doc(db, dPath(A, cA1, 'dA1'))));
});

test('signed-in user without role cannot write delegates', async () => {
  await assertFails(upd(ctx('noRole'), A, cA1, 'dA1'));
});

// ---------- companies ----------
test('companies: scoped writes; invite claim admin counter still works', async () => {
  await assertSucceeds(updateDoc(doc(ctx('compAdmin'), `organizations/${A}/companies/${cA1}`), { phone: '1' }));
  await assertFails(updateDoc(doc(ctx('compAdmin'), `organizations/${A}/companies/${cA2}`), { phone: '1' }));
  await assertFails(updateDoc(doc(ctx('anon'), `organizations/${A}/companies/${cA1}`), { phone: '1' }));
  await assertFails(updateDoc(doc(ctx('delegate'), `organizations/${A}/companies/${cA1}`), { phone: '1' }));
  await assertSucceeds(setDoc(doc(ctx('orgAdmin'), `organizations/${A}/companies/newC`), { name: 'n' }));
  await assertFails(setDoc(doc(ctx('orgAdmin'), `organizations/${B}/companies/newC`), { name: 'n' }));
  await assertFails(setDoc(doc(ctx('compAdmin'), `organizations/${A}/companies/newC2`), { name: 'n' }));
  // Angular invite claim: brand-new user (no users doc yet) bumps admins by 1
  await assertSucceeds(updateDoc(doc(ctx('newUser'), `organizations/${A}/companies/${cA2}`), { admins: increment(1), updatedAt: 1 }));
  await assertFails(updateDoc(doc(ctx('newUser'), `organizations/${A}/companies/${cA2}`), { admins: increment(5) }));
});

// ---------- branches / penalty rules ----------
test('branches: staff in own org write; delegates/anon/other org denied', async () => {
  await assertSucceeds(updateDoc(doc(ctx('compAdmin'), `organizations/${A}/branches/br-${cA1}`), { name: 'x' }));
  await assertFails(updateDoc(doc(ctx('compAdmin'), `organizations/${B}/branches/br-${cB1}`), { name: 'x' }));
  await assertFails(updateDoc(doc(ctx('delegate'), `organizations/${A}/branches/br-${cA1}`), { name: 'x' }));
  await assertFails(updateDoc(doc(ctx('anon'), `organizations/${A}/branches/br-${cA1}`), { name: 'x' }));
  await assertSucceeds(updateDoc(doc(ctx('branchesMkt'), 'branches/root1'), { name: 'x' }));
  await assertFails(updateDoc(doc(ctx('anon'), 'branches/root1'), { name: 'x' }));
  await assertFails(updateDoc(doc(ctx('delegate'), 'branches/root1'), { name: 'x' }));
});

test('penalty_rules: staff write, delegate/anon denied', async () => {
  await assertSucceeds(setDoc(doc(ctx('hr'), 'penalty_rules/r2'), { a: 1 }));
  await assertFails(setDoc(doc(ctx('anon'), 'penalty_rules/r3'), { a: 1 }));
  await assertFails(setDoc(doc(ctx('delegate'), 'penalty_rules/r3'), { a: 1 }));
});

// ---------- Angular company-admin + app supervisor main queries ----------
test('Angular company-admin dashboard queries', async () => {
  const db = ctx('compAdmin');
  await assertSucceeds(getDocs(collection(db, `organizations/${A}/companies/${cA1}/delegates`)));
  await assertSucceeds(getDocs(query(collectionGroup(db, 'delegates'), where('companyUID', '==', cA1))));
  await assertSucceeds(getDocs(query(collectionGroup(db, 'requests'),
    where('organizationUID', '==', A), where('companyUID', '==', cA1))));
  await assertSucceeds(getDoc(doc(db, 'users/compAdmin')));
});

test('Angular org-admin dashboard queries', async () => {
  const db = ctx('orgAdmin');
  await assertSucceeds(getDocs(query(collectionGroup(db, 'delegates'), where('organizationUID', '==', A))));
  await assertSucceeds(getDocs(collection(db, `organizations/${A}/companies`)));
});

test('App supervisor screens main queries (company_supervisor)', async () => {
  const db = ctx('compSup');
  await assertSucceeds(getDocs(query(collectionGroup(db, 'delegates'), where('organizationUID', '==', A))));
  await assertSucceeds(getDocs(query(collectionGroup(db, 'delegates'), where('uid', '==', 'dA1'))));
  await assertSucceeds(getDocs(collectionGroup(db, 'companies')));
  await assertSucceeds(getDocs(collection(db, 'branches')));
  await assertSucceeds(getDocs(collection(db, 'penalty_rules')));
  await assertSucceeds(getDoc(doc(db, `organizations/${A}/companies/${cA1}`)));
});
