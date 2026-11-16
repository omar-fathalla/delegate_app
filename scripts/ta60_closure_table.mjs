/** Generate closure classification rows for ta60-prod-compat.md (Stream 1). */
import { runFirestoreCompatHarness, isDeliberateFirestoreRegression } from '../test/rules/ta60/firestore_compat.mjs';

const FLOW = {
  'delegate CG delegates where nationalityID == own (identifier resolve, try/catch)':
    ['Delegate login / identifier resolve (OTP path fallback)', 'auth login'],
  'delegate users where phoneNumber == supervisorPhone':
    ['Delegate attendance check-in notify lookup (try/catch)', 'attendance check-in → supervisor notification'],
  'supervisor CG delegates phoneNumber dup-check (try/catch)':
    ['Supervisor new-delegate registration dup check', 'admin registration / chain attach'],
  'supervisor CG delegates nationalId dup-check (try/catch)':
    ['Supervisor new-delegate registration dup check', 'admin registration'],
  'supervisor CG delegates receiptCode dup-check (try/catch)':
    ['Supervisor new-delegate registration receipt dup', 'admin registration'],
  'supervisor delegate_requests where receiptCode (try/catch)':
    ['Supervisor registration receiptCode dup', 'admin registration'],
  'supervisor users where role in [super-admin...] (notify, try/catch)':
    ['Penalty fan-out staff lookup', 'penalties → notify staff (TA-35 callable primary)'],
  'supervisor read company broadcast notifications (delegateUid in [supervisor_co, company_co])':
    ['Supervisor notification bell (company broadcasts)', 'notifications bell'],
  'supervisor update delegate doc status (suspend)':
    ['Supervisor delegate suspend/hold', 'admin delegates → suspend'],
  'supervisor registration nationalId dup-check listen (nationalId query)':
    ['Supervisor registration realtime dup listener', 'admin registration'],
  'tech support approve request (update status approved)':
    ['TS approve subscription request (unbatched harness)', 'admin subscription requests (1.14.3 uses WriteBatch)'],
  'super-admin approve request (update status approved, main step 1)':
    ['SA approve subscription request (unbatched harness)', 'admin subscription requests (1.14.3 uses WriteBatch)'],
  'tech support provision delegate set(merge) status active (main step 2c, unbatched)':
    ['TS provision delegate (unbatched harness)', 'admin approve (1.14.3 batched)'],
  'any staff users list all (private label perms: users get())':
    ['Private Label hub user search', 'private label permissions hub (marketing / super-admin)'],
  'supervisor read company broadcasts delegateUid in [supervisor_co, company_co, all_company_supervisors]':
    ['Supervisor notification bell broadcasts', 'notifications bell'],
  'ts approve new delegate step1 update delegate_requests approved':
    ['TS approve step1 (unbatched harness)', 'admin subscription requests (batched in app)'],
  'ts approve step2c delegate set(merge) active':
    ['TS provision step2c unbatched', 'admin approve (batched in app)'],
  'sa approve new delegate step1 update delegate_requests approved':
    ['SA approve step1 (unbatched harness)', 'admin subscription requests (batched in app)'],
  'anonymous (<=v1.14.1) CG delegates phone login query':
    ['Legacy anonymous phone login', 'login (≤1.14.1)'],
  'anonymous (<=v1.14.1) add attendance check-in':
    ['Legacy anonymous attendance write', 'attendance (≤1.14.1)'],
};

function classify(row) {
  const { area, name } = row;
  if (area === 'APP-OLD' || name.includes('<=v1.14.1')) {
    return { cls: 'c', firebase: 'n/a (intentional close)', decision: '' };
  }
  if (
    name.includes('try/catch)') ||
    name.includes('try/catch') ||
    name === 'delegate users where phoneNumber == supervisorPhone'
  ) {
    const fb = name.includes('dup-check') || name.includes('receiptCode')
      ? 'Yes — narrow org-scoped CG/delegate_requests list (Stream 2 / P2–P3a; no REQUEST CHANGES widen)'
      : name.includes('notify')
        ? 'Yes — `listGlobalNotifyStaff` callable (live TA-35); rules deny client enumerate'
        : 'Yes — partial degrade; app uses queryAllSettled / login fallbacks';
    return { cls: 'd', firebase: fb, decision: '' };
  }
  if (name.includes('approve') || name.includes('provision') || name.includes('step2c') || name.includes('step1')) {
    return {
      cls: 'd',
      firebase: 'Yes — 1.14.3 approval uses WriteBatch; harness tests forbidden unbatched path (H1/H2). No client widen.',
      decision: '',
    };
  }
  if (name.includes('list bell:')) {
    const role = name.split(' ')[0];
    const webRoles = new Set(['oa']);
    const cls = webRoles.has(role) ? 'a,b' : 'd';
    const screen =
      role === 'oa'
        ? 'Org-admin notification bell (live web tashil + app)'
        : `${role} staff notification bell`;
  return {
      cls,
      firebase:
        'Yes — split cheap `allow list` on `/notifications` (P0-A); app uses `queryAllSettled` so each row is partial deny unless all queries fail',
      decision: '',
      screen,
      flow: 'notifications bell / header',
    };
  }
  if (
    name === 'supervisor read company broadcast notifications (delegateUid in [supervisor_co, company_co])' ||
    name === 'supervisor read company broadcasts delegateUid in [supervisor_co, company_co, all_company_supervisors]'
  ) {
    return {
      cls: 'd',
      firebase:
        'Yes — P0-A notification list wiring; bell merges via `queryAllSettled` (other uid queries may still succeed)',
      decision: '',
    };
  }
  if (name === 'any staff users list all (private label perms: users get())') {
    return {
      cls: 'b',
      firebase: 'Yes — replace with scoped `users` list by role/org (private-label search); not full collection scan',
      decision: '',
    };
  }
  if (name === 'supervisor update delegate doc status (suspend)') {
    return {
      cls: 'b',
      firebase: 'Maybe — narrow supervisor status-only update in company; expr-budget risk if nested helpers run',
      decision: 'YES — if Stream 2 cannot land narrow suspend without HR/delegate write widen',
    };
  }
  if (name === 'supervisor registration nationalId dup-check listen (nationalId query)') {
    return { cls: 'b', firebase: 'Yes — org-scoped CG dup list (P2)', decision: '' };
  }
  return { cls: 'b', firebase: 'Review', decision: '' };
}

const r = await runFirestoreCompatHarness();
const rows = r.rows
  .filter((row) => row.regression && isDeliberateFirestoreRegression(row.name))
  .map((row, i) => {
    const c = classify(row);
    const flow = FLOW[row.name] ?? ['—', row.area];
    return {
      id: `FS-${String(i + 1).padStart(2, '0')}`,
      area: row.area,
      name: row.name,
      class: c.cls,
      screen: c.screen ?? flow[0],
      flow: c.flow ?? flow[1],
      firebaseOnly: c.firebase,
      decision: c.decision,
    };
  });

const decisions = rows.filter((x) => x.decision.startsWith('YES'));
console.log(JSON.stringify({ count: rows.length, decisions: decisions.map((d) => d.id + ' ' + d.name) }, null, 2));
import fs from 'fs';
fs.writeFileSync('/tmp/ta60-closure-table.json', JSON.stringify(rows, null, 2));