import test from 'node:test';
import assert from 'node:assert/strict';
import {
  runFirestoreCompatHarness,
  BELL_LIVE_ALLOW_TARGETS,
  BELL_PHONE_PROBE_MATRIX,
  shapeCZeroPrefixFromPhones,
  STAFF_SHAPE_C_PHONE,
} from './ta60/firestore_compat.mjs';
import { runStorageCompatHarness } from './ta60/storage_compat.mjs';

test('TA-60 bell shape (c): 0+prefix probe matrix', () => {
  const row = BELL_PHONE_PROBE_MATRIX.find((x) => x.shape === 'c');
  assert.ok(row?.label?.includes('0+'), 'shape (c) documents 0+ prefix');
  assert.deepEqual(shapeCZeroPrefixFromPhones(['01000000001', STAFF_SHAPE_C_PHONE]), [`0${STAFF_SHAPE_C_PHONE}`]);
});

test('TA-60 firestore: live prod vs candidate (main v1.14.2 + web shapes)', async () => {
  const r = await runFirestoreCompatHarness();
  assert.equal(r.unexpected.length, 0, `unexpected regressions: ${r.unexpected.map(x => x.name).join('; ')}`);
  const isExprLimitMsg = (msg) => /maximum of 1000 expressions|limit exceeded/i.test(String(msg || ''));
  const exprLimit = r.unexpected.filter((x) => isExprLimitMsg(x.candMsg));
  assert.equal(exprLimit.length, 0, `expression-limit errors: ${exprLimit.map(x => x.name).join('; ')}`);
  if (r.bellCountIssues?.length) {
    console.warn(`bell allow-count drift vs live targets ${JSON.stringify(BELL_LIVE_ALLOW_TARGETS)}: ${r.bellCountIssues.join('; ')}`);
  }
  assert.equal(r.bellCountIssues?.length ?? 0, 0, `bell counts: ${(r.bellCountIssues || []).join('; ')}`);
  assert.equal(
    r.bellSimulationIssues?.length ?? 0,
    0,
    `getNotifications() sim doc counts: ${(r.bellSimulationIssues || []).join('; ')}`,
  );
  console.log(
    `firestore harness: ${r.total} cases, ${r.deliberate.length} deliberate regressions, ` +
      `0 unexpected; bell sim ${JSON.stringify(r.bellLiveSim?.uniqueDocs)}`,
  );
});

test('TA-60 storage: live prod vs candidate', async () => {
  const r = await runStorageCompatHarness();
  assert.equal(r.unexpected.length, 0, `unexpected regressions: ${r.unexpected.map(x => x.name).join('; ')}`);
  console.log(`storage harness: ${r.total} cases, 0 regressions`);
});