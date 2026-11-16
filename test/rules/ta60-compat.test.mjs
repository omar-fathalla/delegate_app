import test from 'node:test';
import assert from 'node:assert/strict';
import {
  runFirestoreCompatHarness,
  BELL_LIVE_ALLOW_TARGETS,
  BELL_PHONE_PROBE_MATRIX,
  shapeCZeroPrefixFromPhones,
  STAFF_SHAPE_C_PHONE,
  runBellGetNotificationsSimulation,
  staffG5PhoneDocCounts,
  staffRealProdToken,
  staffWithMintedPhones,
} from './ta60/firestore_compat.mjs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { runStorageCompatHarness } from './ta60/storage_compat.mjs';

test('TA-60 bell shape (c): 0+prefix probe matrix', () => {
  const row = BELL_PHONE_PROBE_MATRIX.find((x) => x.shape === 'c');
  assert.ok(row?.label?.includes('0+'), 'shape (c) documents 0+ prefix');
  assert.deepEqual(shapeCZeroPrefixFromPhones(['01000000001', STAFF_SHAPE_C_PHONE]), [`0${STAFF_SHAPE_C_PHONE}`]);
});

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const FS_PORT = Number(process.env.LOCAL_CI_FIRESTORE_PORT || 8080);
const CAND_RULES = process.env.CAND || path.join(ROOT, 'firestore.rules');

test('TA-60 staff JWT phones: pre-mint short counts + G5 deny on candidate', async () => {
  const cand = await initializeTestEnvironment({
    projectId: 'demo-ta60-cand-pre-mint',
    firestore: {
      rules: fs.readFileSync(CAND_RULES, 'utf8'),
      host: '127.0.0.1',
      port: FS_PORT,
    },
  });
  const g5Pre = await staffG5PhoneDocCounts(cand, staffRealProdToken);
  for (const [role, n] of Object.entries(g5Pre)) {
    if (role === 'delegate') continue;
    assert.equal(n, 0, `${role}: pre-mint G5 phone list must DENY (0 docs)`);
  }
  const postG5 = await staffG5PhoneDocCounts(cand, staffWithMintedPhones);
  const g5Gained = Object.entries(postG5).filter(([role, n]) => role !== 'delegate' && n > 0);
  assert.ok(g5Gained.length > 0, 'post-mint staff G5 must return docs for at least one role');
  await cand.cleanup();
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
  assert.equal(
    r.staffSelfwriteIssues?.length ?? 0,
    0,
    `staff self-write bell attack: ${(r.staffSelfwriteIssues || []).join('; ')}`,
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