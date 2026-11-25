/**
 * Callable startBillingCycle (Phase 2 item 2). Replaces web W7
 * clearAllDeferredPayments$ with an idempotent, resumable org-admin run.
 *
 * Shadow mode: adds billing_cycle_reset holds and writes only to
 * billing_cycles or shadow fields (holds, statusHistory, priors). It does
 * not write status, statusReason, company billing counters, or isPrinted.
 * Real company / isPrinted writes run only when HOLDS_AUTHORITY_MODE is
 * authoritative, and previous values are stored on the run doc.
 *
 * Deploy: functions:tashil-mobile-notifications:startBillingCycle
 * Mode is process.env.HOLDS_AUTHORITY_MODE (default shadow). Flip or roll
 * back on tashil-dev with scripts/holds_authority_mode.sh. Do not deploy
 * suspendExpiredSubscriptions with this function or with a mode flip.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {FieldPath, FieldValue} from "firebase-admin/firestore";
import {
  HOLD_BILLING_CYCLE_RESET,
  holdsMode,
  planHoldChange,
  type HoldChangePlan,
  type HoldsCaller,
} from "./holds";
import {
  BILLING_BATCH_OPS,
  BILLING_CYCLES,
  BILLING_PAGE_SIZE,
  BILLING_PHASE_COMPANIES,
  BILLING_PHASE_DELEGATES,
  BILLING_SOURCE,
  BILLING_STATE_DONE,
  addCount,
  addReason,
  billingRunId,
  claimBillingRun,
  decideStartBillingCycle,
  planCompanyBillingWrite,
  planDelegatePrintedWrite,
  shouldWriteCompanyBilling,
  finishBillingRun,
  parseDelegatePath,
  periodCodeAt,
  skipReasonForDelegate,
  yieldBillingRun,
  partitionPriors,
  priorShardId,
  BILLING_PRIOR_DOC_CAP,
  BILLING_PRIOR_SHARDS,
  type BillingRunState,
} from "./billing_cycle";
import {appAddedDelegateUids, coveredDelegateUids} from "./subscription_jobs";
import {parsePeriodCode} from "./subscription_logic";
import {claimBackedCaller} from "./staff_claims";

if (admin.apps.length === 0) admin.initializeApp();

type Db = FirebaseFirestore.Firestore;

const opts = {timeoutSeconds: 120, memory: "512MB" as const};
const LEASE_MS = 120_000;
const TIME_BUDGET_MS = 80_000;

function fail(code: functions.https.FunctionsErrorCode, reason: string): never {
  throw new functions.https.HttpsError(code, reason, {reason});
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

async function loadCaller(ctx: functions.https.CallableContext): Promise<HoldsCaller> {
  if (!ctx.auth || ctx.auth.token.firebase?.sign_in_provider === "anonymous") {
    fail("unauthenticated", "sign_in_required");
  }
  const snap = await admin.firestore().collection("users").doc(ctx.auth.uid).get();
  if (!snap.exists) fail("permission-denied", "caller_not_staff");
  // TAS-23: role and scope from the token claims, not the users doc.
  const d = claimBackedCaller(snap.data(), ctx.auth.token);
  return {
    uid: ctx.auth.uid,
    role: d.role,
    organizationUID: d.organizationUID,
    companyUID: d.companyUID,
    isActive: d.isActive,
  };
}

function serializeHolds(holds: HoldChangePlan["nextHolds"]): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, entry] of Object.entries(holds)) {
    if (!entry) continue;
    const clean: Record<string, string> = {};
    for (const [k, v] of Object.entries(entry)) {
      if (typeof v === "string" && v) clean[k] = v;
    }
    out[key] = clean;
  }
  return out;
}

class Batcher {
  private batch: FirebaseFirestore.WriteBatch;
  private count = 0;
  writes = 0;
  constructor(private db: Db) {
    this.batch = db.batch();
  }
  async set(ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown>, merge = false): Promise<void> {
    this.batch.set(ref, data, {merge});
    await this.tick();
  }
  async update(ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown>): Promise<void> {
    this.batch.update(ref, data as FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>);
    await this.tick();
  }
  private async tick(): Promise<void> {
    this.count++;
    this.writes++;
    if (this.count >= BILLING_BATCH_OPS) await this.flush();
  }
  async flush(): Promise<void> {
    if (this.count === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.count = 0;
  }
}

async function loadOrClaimRun(
  db: Db,
  args: {
    orgId: string;
    cycleId: string;
    periodCode: string;
    actor: string;
    mode: string;
    nowMs: number;
    at: string;
    leaseMs: number;
  },
): Promise<{action: string; state: BillingRunState; ref: FirebaseFirestore.DocumentReference}> {
  const ref = db.collection(BILLING_CYCLES).doc(billingRunId(args.orgId, args.cycleId));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? (snap.data() as BillingRunState) : null;
    const claim = claimBillingRun(existing, args);
    if (claim.action === "create" || claim.action === "resume") {
      const stored: Record<string, unknown> = {
        ...claim.state,
        counts: claim.state.counts,
        updatedAtTs: FieldValue.serverTimestamp(),
      };
      tx.set(ref, stored, {merge: true});
    }
    return {action: claim.action, state: claim.state, ref};
  }).then(async (claimed) => {
    if (claimed.action === "resume" || claimed.action === "noop_done") {
      return {...claimed, state: await mergePriorShards(ref, claimed.state)};
    }
    return claimed;
  });
}

async function mergePriorShards(
  ref: FirebaseFirestore.DocumentReference,
  state: BillingRunState,
): Promise<BillingRunState> {
  const snap = await ref.collection(BILLING_PRIOR_SHARDS).get();
  if (snap.empty) return state;
  const companyPriors = {...(state.companyPriors || {})} as Record<string, NonNullable<BillingRunState["companyPriors"]>[string]>;
  const delegatePriors = {...(state.delegatePriors || {})} as Record<string, NonNullable<BillingRunState["delegatePriors"]>[string]>;
  for (const doc of snap.docs) {
    const data = doc.data() as {kind?: string; key?: string; prior?: Record<string, unknown>};
    if (!data.key || !data.prior) continue;
    if (data.kind === "company" && !companyPriors[data.key]) {
      companyPriors[data.key] = data.prior as unknown as typeof companyPriors[string];
    } else if (data.kind === "delegate" && !delegatePriors[data.key]) {
      delegatePriors[data.key] = data.prior as unknown as typeof delegatePriors[string];
    }
  }
  return {...state, companyPriors, delegatePriors};
}

async function saveRun(
  ref: FirebaseFirestore.DocumentReference,
  state: BillingRunState,
): Promise<void> {
  const companies = partitionPriors(state.companyPriors, BILLING_PRIOR_DOC_CAP);
  const delegates = partitionPriors(state.delegatePriors, BILLING_PRIOR_DOC_CAP);
  const writer = new Batcher(ref.firestore);
  for (const [key, prior] of Object.entries(companies.tail)) {
    await writer.set(ref.collection(BILLING_PRIOR_SHARDS).doc(priorShardId("company", key)), {
      kind: "company", key, prior,
    }, true);
  }
  for (const [key, prior] of Object.entries(delegates.tail)) {
    await writer.set(ref.collection(BILLING_PRIOR_SHARDS).doc(priorShardId("delegate", key)), {
      kind: "delegate", key, prior,
    }, true);
  }
  await writer.flush();
  await ref.set({
    ...state,
    companyPriors: companies.head,
    delegatePriors: delegates.head,
    priorShardCount: companies.spilled + delegates.spilled,
    updatedAtTs: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function resetCompanyPage(
  db: Db,
  state: BillingRunState,
  startedAt: number,
): Promise<BillingRunState> {
  const companies = db.collection(`organizations/${state.orgId}/companies`);
  let q: FirebaseFirestore.Query = companies.orderBy(FieldPath.documentId()).limit(BILLING_PAGE_SIZE);
  if (state.cursor) {
    q = q.startAfter(state.cursor);
  }
  const snap = await q.get();
  const writer = new Batcher(db);
  const priors = {...(state.companyPriors || {})};
  const mode = state.mode || "";
  let lastId = state.cursor;
  for (const doc of snap.docs) {
    const data = (doc.data() || {}) as Record<string, unknown>;
    const planned = planCompanyBillingWrite(mode, data);
    if (!priors[doc.id]) priors[doc.id] = planned.prior;
    addCount(state.counts, "companies");
    if (planned.visibleWrite && shouldWriteCompanyBilling(mode)) {
      await writer.update(doc.ref, {
        ...planned.visibleWrite,
        updatedAt: FieldValue.serverTimestamp(),
      });
      addCount(state.counts, "companiesReset");
    }
    lastId = doc.id;
  }
  state.companyPriors = priors;
  await writer.flush();
  if (snap.size < BILLING_PAGE_SIZE) {
    state.phase = BILLING_PHASE_DELEGATES;
    state.cursor = "";
    state.companiesReset = true;
  } else {
    state.cursor = lastId;
  }
  state.updatedAt = new Date().toISOString();
  void startedAt;
  return state;
}

async function resetDelegatePage(
  db: Db,
  state: BillingRunState,
  ctx: {
    appAdded: Set<string>;
    covered: Set<string>;
    at: string;
    actor: string;
    mode: string;
  },
): Promise<BillingRunState> {
  let q: FirebaseFirestore.Query = db.collectionGroup("delegates")
    .where("organizationUID", "==", state.orgId)
    .orderBy(FieldPath.documentId())
    .limit(BILLING_PAGE_SIZE);
  if (state.cursor) {
    // Collection-group document IDs are the full path.
    q = q.startAfter(state.cursor);
  }
  const snap = await q.get();
  const writer = new Batcher(db);
  const delegatePriors = {...(state.delegatePriors || {})};
  let lastPath = state.cursor;
  for (const doc of snap.docs) {
    addCount(state.counts, "docs");
    lastPath = doc.ref.path;
    const data = (doc.data() || {}) as Record<string, unknown>;
    const skip = skipReasonForDelegate(
      doc.ref.path, data, state.orgId, state.periodCode, ctx.appAdded, ctx.covered,
    );
    if (skip) {
      addReason(state.counts, skip);
      continue;
    }
    const parsed = parseDelegatePath(doc.ref.path);
    if (!parsed) {
      addReason(state.counts, "wrong_org");
      continue;
    }
    const plan = planHoldChange({
      data,
      op: "add",
      hold: HOLD_BILLING_CYCLE_RESET,
      actor: ctx.actor,
      mode: ctx.mode,
      at: ctx.at,
      source: BILLING_SOURCE,
      cycleId: state.cycleId,
      periodCode: state.periodCode,
    });
    if (!plan.ok) {
      addReason(state.counts, plan.reason || "not_actionable");
      continue;
    }
    if (plan.unchanged) {
      addReason(state.counts, "already_held");
      continue;
    }
    const printed = planDelegatePrintedWrite(ctx.mode, data);
    if (!delegatePriors[doc.ref.path]) {
      delegatePriors[doc.ref.path] = printed.prior;
    }
    const update: Record<string, unknown> = {
      holds: serializeHolds(plan.nextHolds),
      statusVersion: plan.statusVersion,
      holdsAuthorityAt: ctx.at,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (printed.visibleWrite) {
      Object.assign(update, printed.visibleWrite);
    }
    if (ctx.mode === "authoritative") {
      update.status = plan.derivedStatus;
      update.statusReason = plan.nextStatusReason === null ?
        FieldValue.delete() : plan.nextStatusReason;
    }
    await writer.update(doc.ref, update);
    await writer.set(doc.ref.collection("statusHistory").doc(), {
      ...plan.history,
      writtenAt: FieldValue.serverTimestamp(),
    });
    addCount(state.counts, "written");
  }
  await writer.flush();
  state.delegatePriors = delegatePriors;
  if (snap.size < BILLING_PAGE_SIZE) {
    return finishBillingRun(state, new Date().toISOString(), Date.now());
  }
  state.cursor = lastPath;
  state.updatedAt = new Date().toISOString();
  return state;
}

export async function runStartBillingCycle(
  db: Db,
  args: {
    orgId: string;
    cycleId: string;
    actor: string;
    now?: Date;
    timeBudgetMs?: number;
  },
): Promise<{
  ok: true;
  state: "running" | "done";
  resumed: boolean;
  unchanged: boolean;
  inProgress?: boolean;
  orgId: string;
  cycleId: string;
  periodCode: string;
  mode: string;
  counts: BillingRunState["counts"];
}> {
  const now = args.now || new Date();
  const at = now.toISOString();
  const nowMs = now.getTime();
  const mode = holdsMode();
  const periodCode = periodCodeAt(now);
  const claimed = await loadOrClaimRun(db, {
    orgId: args.orgId,
    cycleId: args.cycleId,
    periodCode,
    actor: args.actor,
    mode,
    nowMs,
    at,
    leaseMs: LEASE_MS,
  });

  if (claimed.action === "noop_done") {
    return {
      ok: true,
      state: BILLING_STATE_DONE,
      resumed: false,
      unchanged: true,
      orgId: args.orgId,
      cycleId: args.cycleId,
      periodCode: claimed.state.periodCode,
      mode: claimed.state.mode || mode,
      counts: claimed.state.counts,
    };
  }
  if (claimed.action === "in_progress") {
    return {
      ok: true,
      state: "running",
      resumed: false,
      unchanged: false,
      inProgress: true,
      orgId: args.orgId,
      cycleId: args.cycleId,
      periodCode: claimed.state.periodCode,
      mode: claimed.state.mode || mode,
      counts: claimed.state.counts,
    };
  }

  const resumed = claimed.action === "resume";
  let state = claimed.state;
  const deadline = Date.now() + (args.timeBudgetMs ?? TIME_BUDGET_MS);
  const period = parsePeriodCode(state.periodCode) || parsePeriodCode(periodCode);
  const appAdded = new Set((await appAddedDelegateUids(db)).keys());
  const covered = period ? await coveredDelegateUids(db, period) : new Set<string>();

  while (Date.now() < deadline && state.state !== BILLING_STATE_DONE) {
    if (state.phase === BILLING_PHASE_COMPANIES) {
      state = await resetCompanyPage(db, state, Date.now());
    } else {
      state = await resetDelegatePage(db, state, {
        appAdded, covered, at, actor: args.actor, mode: state.mode || mode,
      });
    }
    if (state.state !== BILLING_STATE_DONE && Date.now() >= deadline) {
      state = yieldBillingRun(state, new Date().toISOString(), Date.now());
      break;
    }
  }
  await saveRun(claimed.ref, state);
  functions.logger.info("startBillingCycle", {
    orgId: args.orgId,
    cycleId: args.cycleId,
    state: state.state,
    resumed,
    counts: state.counts,
    mode: state.mode || mode,
  });
  return {
    ok: true,
    state: state.state,
    resumed,
    unchanged: false,
    orgId: args.orgId,
    cycleId: args.cycleId,
    periodCode: state.periodCode,
    mode: state.mode || mode,
    counts: state.counts,
  };
}

export const startBillingCycle = functions.region("us-central1").runWith(opts).https.onCall(
  async (data, ctx) => {
    try {
      const caller = await loadCaller(ctx);
      const p = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
      const orgId = str(p.orgId) || str(p.organizationUID);
      const cycleId = str(p.cycleId);
      const decision = decideStartBillingCycle(caller, orgId, cycleId);
      if (!decision.ok) {
        const code = decision.reason === "invalid_org" || decision.reason === "invalid_cycle" ?
          "invalid-argument" : "permission-denied";
        fail(code, decision.reason);
      }
      return await runStartBillingCycle(admin.firestore(), {
        orgId, cycleId, actor: caller.uid,
      });
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      functions.logger.error("startBillingCycle failed", {message: String(e)});
      fail("internal", "unavailable");
    }
  },
);
