import test from 'node:test';
import assert from 'node:assert/strict';
import { runFirestoreCompatHarness } from './ta60/firestore_compat.mjs';
import { runStorageCompatHarness } from './ta60/storage_compat.mjs';

test('TA-60 firestore: live prod vs candidate (main v1.14.2 + web shapes)', async () => {
  const r = await runFirestoreCompatHarness();
  assert.equal(r.unexpected.length, 0, `unexpected regressions: ${r.unexpected.map(x => x.name).join('; ')}`);
  const isExprLimitMsg = (msg) => /maximum of 1000 expressions|limit exceeded/i.test(String(msg || ''));
  const exprLimit = r.unexpected.filter((x) => isExprLimitMsg(x.candMsg));
  assert.equal(exprLimit.length, 0, `expression-limit errors: ${exprLimit.map(x => x.name).join('; ')}`);
  console.log(`firestore harness: ${r.total} cases, ${r.deliberate.length} deliberate regressions, 0 unexpected`);
});

test('TA-60 storage: live prod vs candidate', async () => {
  const r = await runStorageCompatHarness();
  assert.equal(r.unexpected.length, 0, `unexpected regressions: ${r.unexpected.map(x => x.name).join('; ')}`);
  console.log(`storage harness: ${r.total} cases, 0 regressions`);
});