/**
 * Emulator test (TAS-87): stats increments, the event guard, and the backfill.
 *
 *   bash scripts/emulators_exec.sh --only firestore --project demo-tas87 \
 *     "node --test functions/test/delegate_stats.emulator.test.js"
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const live = !!process.env.FIRESTORE_EMULATOR_HOST;

const CAIRO = "القاهرة";
const ORG = "seed-fake-tas87-org";

test("increments, duplicate events, no-op updates, then backfill agrees", {skip: !live}, async () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "demo-tas87"});
  const {applyDelegateStats} = require("../lib/delegate_stats");
  const L = require("../lib/delegate_stats_logic");
  const {run} = require("../scripts/backfill-delegate-stats");
  const db = admin.firestore();
  const dp = (co, u) => `organizations/${ORG}/companies/${co}/delegates/${u}`;
  const orgStats = async () => (await db.doc(`organizations/${ORG}/stats/delegates`).get()).data();
  const coStats = async (co) => (await db.doc(`organizations/${ORG}/companies/${co}/stats/delegates`).get()).data();

  await db.doc(`organizations/${ORG}`).set({name: "fake"});
  await db.doc(`organizations/${ORG}/companies/c1`).set({name: "fake c1"});
  await db.doc(`organizations/${ORG}/companies/c2`).set({name: "fake c2"});

  const a = {status: "active", city: CAIRO, position: "Promoter", organizationUID: ORG, companyUID: "c1",
    documents: [{documentKey: "insuranceLetter", receiptCode: "R"}]};
  await db.doc(dp("c1", "u1")).set(a);
  assert.equal(await applyDelegateStats(db, "ev-1", ORG, "c1", null, a), "applied");
  assert.equal(await applyDelegateStats(db, "ev-1", ORG, "c1", null, a), "duplicate");
  assert.equal(await applyDelegateStats(db, "ev-2", ORG, "c1", a, {...a, name: "x"}), "noop");

  let o = await orgStats();
  assert.equal(o.total, 1);
  assert.equal(o.active, 1);
  assert.equal(o.s1InsuranceDocs, 1);
  assert.equal(o.byCity[CAIRO].Promoter, 1);
  assert.deepEqual(o.byCompany.c1, {total: 1, active: 1});
  assert.equal((await coStats("c1")).byCity[CAIRO].Promoter, 1);

  // Move u1 from c1 to c2 (delete + create), and make it pending.
  const b = {...a, companyUID: "c2", status: "pending"};
  await db.doc(dp("c1", "u1")).delete();
  await db.doc(dp("c2", "u1")).set(b);
  await applyDelegateStats(db, "ev-3", ORG, "c1", a, null);
  await applyDelegateStats(db, "ev-4", ORG, "c2", null, b);
  o = await orgStats();
  assert.equal(o.total, 1);
  assert.equal(o.active, 0);
  assert.deepEqual(o.byCompany.c1, {total: 0, active: 0});
  assert.equal(o.byCompany.c2.total, 1);
  assert.equal(o.byCompany.c2.active || 0, 0, "a zero delta is never written");
  assert.equal((await coStats("c1")).total, 0);
  assert.equal((await coStats("c2")).total, 1);

  // A delegate written without the trigger: the dry-run sees the drift, --apply fixes it.
  await db.doc(dp("c2", "u2")).set({...a, companyUID: "c2"});
  const quiet = () => {};
  const dry = await run(db, L, {project: "demo-tas87", apply: false, pageSize: 1}, quiet);
  assert.equal(dry.delegatesScanned, 2);
  assert.ok(dry.differ >= 2, "org and c2 differ");
  assert.equal(dry.oldWebOrgsDifferent, 0);
  assert.equal(dry.oldWebCompaniesDifferent, 0);
  const applied = await run(db, L, {project: "demo-tas87", apply: true, pageSize: 2}, quiet);
  assert.ok(applied.written >= 2);
  const again = await run(db, L, {project: "demo-tas87", apply: false, pageSize: 500}, quiet);
  assert.equal(again.differ, 0);
  assert.equal(again.missing, 0);
  o = await orgStats();
  assert.equal(o.total, 2);
  assert.equal(o.byCity[CAIRO].Promoter, 2);

  // The trigger keeps working on top of a backfilled doc.
  await applyDelegateStats(db, "ev-5", ORG, "c2", {...a, companyUID: "c2"}, null);
  assert.equal((await orgStats()).total, 1);
  const guard = await db.doc("_delegate_stats_events/ev-1").get();
  assert.ok(guard.exists && guard.data().expireAt);
});
