/**
 * onDelegateStatsWrite (TAS-87): keeps the delegate stats docs that the web
 * dashboards read instead of every delegate doc:
 *   organizations/{orgId}/stats/delegates
 *   organizations/{orgId}/companies/{companyId}/stats/delegates
 *
 * Each write of organizations/{orgId}/companies/{companyId}/delegates/{id}
 * becomes a delta (before minus after, see delegate_stats_logic.ts) applied
 * with FieldValue.increment. A move between companies is a delete in one
 * path and a create in the other, so both companies are corrected.
 *
 * Idempotency: one batch holds create(_delegate_stats_events/{eventId}) and
 * the increments. A redelivered event fails the create with ALREADY_EXISTS
 * and nothing is counted twice. Writes that do not change a counted field
 * (most updates) write nothing at all.
 *
 * Never throws on bad data. Write failures are retried (retry: true) for at
 * most an hour, then dropped; the backfill script repairs any drift:
 *   node scripts/backfill-delegate-stats.js --project tashil-dev [--apply]
 *
 * Deploy: functions:tashil-mobile-notifications:onDelegateStatsWrite
 */
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {
  Data,
  Delta,
  STATS_DOC_ID,
  STATS_SCHEMA_VERSION,
  nestDeltas,
  planDelegateStats,
} from "./delegate_stats_logic";

if (admin.apps.length === 0) admin.initializeApp();

export const STATS_EVENTS_COLLECTION = "_delegate_stats_events";
const MAX_EVENT_AGE_MS = 60 * 60 * 1000;
const EVENT_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const ALREADY_EXISTS = 6;

type Db = admin.firestore.Firestore;

/** Applies one delegate write. Returns what it did (for logs and tests). */
export async function applyDelegateStats(
  db: Db,
  eventId: string,
  orgId: string,
  companyId: string,
  before: Data,
  after: Data,
): Promise<"noop" | "applied" | "duplicate"> {
  const plan = planDelegateStats(before, after, companyId);
  if (!plan.org.length && !plan.company.length) return "noop";

  const inc = (v: number) => admin.firestore.FieldValue.increment(v);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.create(db.collection(STATS_EVENTS_COLLECTION).doc(eventId.replace(/\//g, "_")), {
    orgId,
    companyId,
    at: now,
    expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + EVENT_TTL_MS),
  });
  const write = (path: string, deltas: Delta[], extra: Record<string, unknown>) => {
    if (!deltas.length) return;
    batch.set(db.doc(path), {
      ...nestDeltas(deltas, inc),
      ...extra,
      schemaVersion: STATS_SCHEMA_VERSION,
      updatedAt: now,
    }, {merge: true});
  };
  write(`organizations/${orgId}/stats/${STATS_DOC_ID}`, plan.org, {orgId});
  write(`organizations/${orgId}/companies/${companyId}/stats/${STATS_DOC_ID}`, plan.company, {orgId, companyId});

  try {
    await batch.commit();
    return "applied";
  } catch (e) {
    if ((e as {code?: unknown})?.code === ALREADY_EXISTS) return "duplicate";
    throw e;
  }
}

export const onDelegateStatsWrite = onDocumentWritten(
  {
    document: "organizations/{orgId}/companies/{companyId}/delegates/{delegateId}",
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 20,
    retry: true,
  },
  async (event) => {
    const ageMs = Date.now() - Date.parse(event.time);
    if (ageMs > MAX_EVENT_AGE_MS) {
      logger.error("delegateStats: dropping old event, run the backfill", {id: event.id, ageMs});
      return;
    }
    const {orgId, companyId, delegateId} = event.params;
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    const result = await applyDelegateStats(admin.firestore(), event.id, orgId, companyId, before, after);
    if (result !== "noop") logger.info("delegateStats", {orgId, companyId, delegateId, result});
  },
);
