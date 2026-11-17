/**
 * Automatic chain links (Mohamed, 17 Nov 2026). See
 * company_chain_autolink_logic.ts for the rules.
 *
 * - autoLinkOnCompanyJoin: a company record appears in a chain
 *   (organizations/{org}/companies/{co} created, e.g. «طلب ضم سلسلة»
 *   approved) -> link every eligible delegate of the company.
 * - autoLinkOnDelegateWrite: a delegate copy is created / becomes active /
 *   its subscription changes (renewal) -> link that delegate everywhere.
 * - autoLinkOnUserStatus: users/{uid} goes back to active.
 * - reconcileCompanyChainLinksDaily: 01:30 Cairo safety net for all companies.
 *
 * Writes go through the Admin SDK (rules do not apply), creates use
 * create() so a doc written meanwhile by an approval is never overwritten,
 * and batches stay at <= 400 operations.
 *
 * Deploy (tashil-dev only until Mohamed says otherwise):
 * functions:tashil-mobile-notifications:autoLinkOnCompanyJoin,
 * functions:tashil-mobile-notifications:autoLinkOnDelegateWrite,
 * functions:tashil-mobile-notifications:autoLinkOnUserStatus,
 * functions:tashil-mobile-notifications:reconcileCompanyChainLinksDaily
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldValue} from "firebase-admin/firestore";
import {
  ChainInfo,
  Coverage,
  Data,
  DelegateCopy,
  buildAutoLinkedCopy,
  chunks,
  delegateWriteNeedsReconcile,
  freeChainIds,
  pickSource,
  planDelegate,
  smartPosition,
  str,
} from "./company_chain_autolink_logic";
import {
  TIME_ZONE,
  isFreePromotion,
  isWithinSubscriptionGrace,
  parseFreePromotionLastDay,
  periodOf,
  requestCoversPeriod,
  coveredUids,
} from "./subscription_logic";

if (admin.apps.length === 0) admin.initializeApp();

type Db = admin.firestore.Firestore;
const BATCH_LIMIT = 400;
const GET_ALL_LIMIT = 100;
const CREATE_PARALLEL = 25;

export interface ReconcileResult {
  companyUID: string;
  chains: number;
  delegates: number;
  eligible: number;
  created: number;
  updatedCopies: number;
  updatedUsers: number;
  skipped: Record<string, number>;
  dryRun: boolean;
  pairsMissing: number;
}

async function getAll(db: Db, refs: admin.firestore.DocumentReference[]) {
  const out: admin.firestore.DocumentSnapshot[] = [];
  for (const part of chunks(refs, GET_ALL_LIMIT)) {
    if (part.length) out.push(...await db.getAll(...part));
  }
  return out;
}

let orgsCache: {at: number; value: Array<{id: string; data: Data}>} | null = null;

/** All organizations, cached 60 s per instance. */
async function loadOrgs(db: Db): Promise<Array<{id: string; data: Data}>> {
  if (orgsCache && Date.now() - orgsCache.at < 60_000) return orgsCache.value;
  const snap = await db.collection("organizations").get();
  const value = snap.docs.map((d) => ({id: d.id, data: (d.data() || {}) as Data}));
  orgsCache = {at: Date.now(), value};
  return value;
}

/** Chains the company is in (the free / hidden chain included if it is in it). */
export async function companyChains(db: Db, companyUID: string): Promise<ChainInfo[]> {
  const orgs = await loadOrgs(db);
  const snaps = await getAll(db, orgs.map((o) => db.doc(`organizations/${o.id}/companies/${companyUID}`)));
  const out: ChainInfo[] = [];
  snaps.forEach((s, i) => {
    if (!s.exists) return;
    const o = orgs[i];
    out.push({id: o.id, name: str(o.data.name) || str(o.data.title) || o.id});
  });
  return out;
}

/** Free chains (فتح الله): config/subscriptions.freeChainOrgUids + org flags. */
export async function loadFreeChains(db: Db): Promise<Set<string>> {
  const cfg = await db.doc("config/subscriptions").get();
  return freeChainIds(cfg.exists ? (cfg.data() as Data) : null, await loadOrgs(db));
}

let coverageCache: {at: number; value: Coverage} | null = null;

/** Who has paid coverage now. Cached 60 s per instance. */
export async function loadCoverage(db: Db, now: Date): Promise<Coverage> {
  if (coverageCache && Date.now() - coverageCache.at < 60_000) return coverageCache.value;
  const cfg = await db.doc("config/subscriptions").get();
  const lastDay = parseFreePromotionLastDay(cfg.exists ? cfg.data() as Data : null);
  const period = periodOf(now);
  const prev = periodOf(new Date(period.startsAt.getTime() - 24 * 3600 * 1000));
  const collect = async (code: string) => {
    const snap = await db.collection("delegate_requests").where("periodCode", "==", code).get();
    const set = new Set<string>();
    for (const d of snap.docs) {
      if (requestCoversPeriod(d.data(), code, lastDay)) for (const u of coveredUids(d.id, d.data())) set.add(u);
    }
    return set;
  };
  const inGrace = isWithinSubscriptionGrace(now);
  const value: Coverage = {
    free: isFreePromotion(now, {freePromotionLastDay: lastDay}),
    periodCode: period.code,
    covered: await collect(period.code),
    inGrace,
    previousPeriodCode: prev.code,
    previousCovered: inGrace ? await collect(prev.code) : new Set(),
    freeChains: freeChainIds(cfg.exists ? (cfg.data() as Data) : null, await loadOrgs(db)),
  };
  coverageCache = {at: Date.now(), value};
  return value;
}

/**
 * Links every eligible delegate of [companyUID] (or only [onlyUid]) to every
 * company chain. Idempotent.
 */
export async function reconcileCompanyChainLinks(
  db: Db,
  companyUID: string,
  opts: {onlyUid?: string; now?: Date; dryRun?: boolean} = {},
): Promise<ReconcileResult> {
  const co = companyUID.trim();
  const res: ReconcileResult = {
    companyUID: co, chains: 0, delegates: 0, eligible: 0, created: 0,
    updatedCopies: 0, updatedUsers: 0, skipped: {}, dryRun: !!opts.dryRun, pairsMissing: 0,
  };
  if (!co) return res;
  const chains = await companyChains(db, co);
  res.chains = chains.length;
  if (chains.length === 0) return res;

  const byUid = new Map<string, DelegateCopy[]>();
  const add = (orgId: string, snap: admin.firestore.DocumentSnapshot) => {
    if (!snap.exists) return;
    const data = (snap.data() || {}) as Data;
    const uid = str(data.uid) || snap.id;
    if (!byUid.has(uid)) byUid.set(uid, []);
    byUid.get(uid)!.push({orgId, data});
  };
  if (opts.onlyUid) {
    const refs = chains.map((c) => db.doc(`organizations/${c.id}/companies/${co}/delegates/${opts.onlyUid}`));
    (await getAll(db, refs)).forEach((s, i) => add(chains[i].id, s));
  } else {
    const lists = await Promise.all(chains.map((c) =>
      db.collection(`organizations/${c.id}/companies/${co}/delegates`).get()));
    lists.forEach((l, i) => l.docs.forEach((d) => add(chains[i].id, d)));
  }
  const uids = [...byUid.keys()];
  res.delegates = uids.length;
  if (!uids.length) return res;

  const users = new Map<string, Data | null>();
  (await getAll(db, uids.map((u) => db.doc(`users/${u}`)))).forEach((s, i) => {
    users.set(uids[i], s.exists ? (s.data() as Data) : null);
  });
  const cov = await loadCoverage(db, opts.now ?? new Date());

  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops && !opts.dryRun) await batch.commit();
    batch = db.batch();
    ops = 0;
  };
  const creates: Array<{ref: admin.firestore.DocumentReference; data: Data}> = [];
  const ts = FieldValue.serverTimestamp();

  for (const uid of uids) {
    const copies = byUid.get(uid)!;
    const plan = planDelegate(uid, copies, users.get(uid) ?? null, chains, cov);
    if (plan.eligible) {
      res.eligible++;
    } else {
      const r = `${plan.reason || "unknown"}${plan.freeEligible ? "_free_only" : ""}`;
      res.skipped[r] = (res.skipped[r] || 0) + 1;
    }
    if (!plan.create.length) continue;
    res.pairsMissing += plan.create.length;
    const source = pickSource(copies);
    if (!source) continue;
    for (const orgId of plan.create) {
      const chain = chains.find((c) => c.id === orgId)!;
      creates.push({
        ref: db.doc(`organizations/${orgId}/companies/${co}/delegates/${uid}`),
        data: {
          ...buildAutoLinkedCopy({source, chain, allNames: plan.allNames}),
          autoLinkedAt: ts, createdAt: ts, updatedAt: ts,
        },
      });
    }
    // Keep the existing copies' chain list and position in step (only
    // when they changed, so the daily run does not rewrite every doc).
    const origin = str(source.data.originOrganizationName) || str(source.data.organizationName);
    const sameList = (v: unknown) => Array.isArray(v) &&
      v.length === plan.allNames.length && plan.allNames.every((n) => v.includes(n));
    for (const c of copies) {
      const name = str(c.data.organizationName) || chains.find((x) => x.id === c.orgId)?.name || "";
      const position = smartPosition(plan.allNames, name, origin);
      if (sameList(c.data.allOrganizationNames) && str(c.data.position) === position) continue;
      batch.set(db.doc(`organizations/${c.orgId}/companies/${co}/delegates/${uid}`), {
        allOrganizationNames: plan.allNames,
        position,
        updatedAt: ts,
      }, {merge: true});
      ops++;
      res.updatedCopies++;
      if (ops >= BATCH_LIMIT) await flush();
    }
    const user = users.get(uid);
    const userNames = Array.isArray(user?.organizationNames) ? user!.organizationNames as unknown[] : [];
    if (user && plan.allNames.some((n) => !userNames.includes(n))) {
      batch.set(db.doc(`users/${uid}`), {
        organizationNames: FieldValue.arrayUnion(...plan.allNames),
        updatedAt: ts,
      }, {merge: true});
      ops++;
      res.updatedUsers++;
      if (ops >= BATCH_LIMIT) await flush();
    }
  }
  if (!opts.dryRun) {
    // Copies first, then the list updates (a copy must exist before the
    // other copies name its chain).
    for (const part of chunks(creates, CREATE_PARALLEL)) {
      const results = await Promise.allSettled(part.map((c) => c.ref.create(c.data)));
      results.forEach((r) => {
        if (r.status === "fulfilled") res.created++;
        else if ((r.reason as {code?: number})?.code !== 6) throw r.reason; // 6 = ALREADY_EXISTS
      });
    }
  }
  await flush();
  return res;
}

export const autoLinkOnCompanyJoin = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 300, memory: "512MB"})
  .firestore.document("organizations/{orgId}/companies/{companyId}")
  .onCreate(async (_snap, context) => {
    const res = await reconcileCompanyChainLinks(admin.firestore(), String(context.params.companyId));
    functions.logger.info("autoLinkOnCompanyJoin", {orgId: context.params.orgId, ...res});
    return null;
  });

export const autoLinkOnDelegateWrite = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .firestore.document("organizations/{orgId}/companies/{companyId}/delegates/{uid}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? (change.before.data() as Data) : null;
    const after = change.after.exists ? (change.after.data() as Data) : null;
    if (!delegateWriteNeedsReconcile(before, after)) return null;
    const uid = str(after?.uid) || String(context.params.uid);
    const res = await reconcileCompanyChainLinks(admin.firestore(), String(context.params.companyId), {onlyUid: uid});
    if (res.created) functions.logger.info("autoLinkOnDelegateWrite", {uid, ...res});
    return null;
  });

export const autoLinkOnUserStatus = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 120, memory: "256MB"})
  .firestore.document("users/{uid}")
  .onUpdate(async (change, context) => {
    const b = change.before.data() as Data;
    const a = change.after.data() as Data;
    if (str(a.role) !== "delegate") return null;
    if (str(a.status) === str(b.status) || str(a.status) !== "active") return null;
    const co = str(a.companyUID);
    if (!co) return null;
    await reconcileCompanyChainLinks(admin.firestore(), co, {onlyUid: String(context.params.uid)});
    return null;
  });

/** Every company that is in at least one chain. */
export async function allCompanyUids(db: Db): Promise<string[]> {
  const snap = await db.collectionGroup("companies").select().get();
  return [...new Set(snap.docs.map((d) => d.id))].filter((id) => id !== "");
}

export const reconcileCompanyChainLinksDaily = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "512MB"})
  .pubsub.schedule("30 1 * * *")
  .timeZone(TIME_ZONE)
  .onRun(async () => {
    const db = admin.firestore();
    let created = 0;
    for (const co of await allCompanyUids(db)) {
      try {
        created += (await reconcileCompanyChainLinks(db, co)).created;
      } catch (e) {
        functions.logger.error("reconcileCompanyChainLinksDaily company failed", {co, e: String(e)});
      }
    }
    functions.logger.info("reconcileCompanyChainLinksDaily", {created});
    return null;
  });
