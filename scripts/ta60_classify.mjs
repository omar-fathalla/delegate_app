import { runFirestoreCompatHarness } from '../test/rules/ta60/firestore_compat.mjs';
import { runStorageCompatHarness } from '../test/rules/ta60/storage_compat.mjs';

function kind(row) {
  const m = String(row.candMsg || '');
  if (m.includes('1000') || m.includes('evaluation error') || m.includes('undefined on object')) return 'A';
  return 'B';
}

const fs = await runFirestoreCompatHarness();
const st = await runStorageCompatHarness();
const a = fs.unexpected.filter((r) => kind(r) === 'A');
const b = fs.unexpected.filter((r) => kind(r) === 'B');
console.log(JSON.stringify({
  firestore: { total: fs.total, unexpected: fs.unexpected.length, deliberate: fs.deliberate.length, A: a.length, B: b.length,
    BNames: b.map((x) => x.name), ANames: a.map((x) => x.name) },
  storage: { total: st.total, unexpected: st.unexpected.length, names: st.unexpected.map((x) => x.name) },
}, null, 2));