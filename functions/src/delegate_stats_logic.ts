/**
 * TAS-87: pure logic for the server-maintained delegate stats docs.
 *
 * The web dashboards used to read every delegate of a chain / company in the
 * browser for two widgets:
 *   - the governorates chart (city x position counts), and
 *   - the financial summary (active / total per company, S1 insurance
 *     letters and approved embassy health certificates from `documents[]`).
 *
 * The trigger (delegate_stats.ts) turns each delegate write into a small
 * delta and applies it with FieldValue.increment to:
 *   organizations/{orgId}/stats/delegates
 *   organizations/{orgId}/companies/{companyId}/stats/delegates
 * The backfill script recomputes the same docs from scratch with
 * `accumulate`, so both paths share these functions.
 *
 * Never throws on bad data: unknown shapes count as "no contribution".
 */

export type Data = Record<string, unknown> | null | undefined;

/** What one delegate doc adds to the stats of its org and its company. */
export interface Contribution {
  total: number;
  active: number;
  s1InsuranceDocs: number;
  embassyHealthCerts: number;
  /** Sanitized city key, or "" when the doc has no usable city. */
  city: string;
  /** Sanitized position key, or "" when the doc has no usable position. */
  position: string;
}

/** A numeric delta at a field path inside a stats doc. */
export interface Delta {
  path: string[];
  value: number;
}

export const STATS_DOC_ID = "delegates";
export const STATS_SCHEMA_VERSION = 1;
const MAX_KEY_LENGTH = 100;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/**
 * A map key that Firestore accepts as a field name: non-empty, bounded,
 * not of the reserved `__x__` form. Anything else becomes "".
 */
export function safeKey(v: unknown): string {
  // Kept as stored (no trim): the web matches the raw value exactly.
  if (!str(v)) return "";
  const s = v as string;
  if (s.length > MAX_KEY_LENGTH) return "";
  if (/^__.*__$/.test(s)) return "";
  return s;
}

function docsOf(data: Record<string, unknown>): Record<string, unknown>[] {
  const docs = data.documents;
  if (!Array.isArray(docs)) return [];
  return docs.filter((d): d is Record<string, unknown> => !!d && typeof d === "object" && !Array.isArray(d));
}

function holderMode(doc: Record<string, unknown>): boolean {
  return !!doc.secondaryURL || !!doc.receiptCode;
}

/**
 * Same rules as the web's financial-computations.ts:
 * - S1: every `insuranceLetter` item with a secondaryURL or receiptCode.
 * - Embassy health: the FIRST `healthCertificate` item is approved and in
 *   holder mode (secondaryURL or receiptCode) -> 1 per delegate.
 */
export function contributionOf(data: Data): Contribution | null {
  if (!data || typeof data !== "object") return null;
  const docs = docsOf(data);
  let s1 = 0;
  for (const d of docs) {
    if (d.documentKey === "insuranceLetter" && holderMode(d)) s1++;
  }
  const health = docs.find((d) => d.documentKey === "healthCertificate");
  const embassy = health && health.documentStatus === "approved" && holderMode(health) ? 1 : 0;
  return {
    total: 1,
    active: data.status === "active" ? 1 : 0,
    s1InsuranceDocs: s1,
    embassyHealthCerts: embassy,
    city: safeKey(data.city),
    position: safeKey(data.position),
  };
}

function addContribution(out: Map<string, Delta>, c: Contribution | null, sign: number, companyId: string | null) {
  if (!c) return;
  const add = (path: string[], v: number) => {
    if (!v) return;
    const k = JSON.stringify(path);
    const cur = out.get(k);
    if (cur) cur.value += sign * v;
    else out.set(k, {path, value: sign * v});
  };
  add(["total"], c.total);
  add(["active"], c.active);
  add(["s1InsuranceDocs"], c.s1InsuranceDocs);
  add(["embassyHealthCerts"], c.embassyHealthCerts);
  if (c.city && c.position) add(["byCity", c.city, c.position], 1);
  if (companyId) {
    add(["byCompany", companyId, "total"], c.total);
    add(["byCompany", companyId, "active"], c.active);
  }
}

/**
 * Deltas for one stats doc. `companyId` is set for the org doc only (it keeps
 * a per-company breakdown for the financial summary). Zero deltas are dropped,
 * so an update that does not touch a counted field returns [].
 */
export function deltasFor(before: Data, after: Data, companyId: string | null = null): Delta[] {
  const out = new Map<string, Delta>();
  addContribution(out, contributionOf(before), -1, companyId);
  addContribution(out, contributionOf(after), +1, companyId);
  return [...out.values()].filter((d) => d.value !== 0);
}

/** Org-doc and company-doc deltas for one delegate write. */
export function planDelegateStats(before: Data, after: Data, companyId: string): {org: Delta[]; company: Delta[]} {
  const cid = safeKey(companyId);
  return {
    org: deltasFor(before, after, cid || null),
    company: deltasFor(before, after, null),
  };
}

/** Nested object for `set(..., {merge: true})`, leaves built by `leaf`. */
export function nestDeltas<T>(deltas: Delta[], leaf: (v: number) => T): Record<string, unknown> {
  const root: Record<string, unknown> = {};
  for (const d of deltas) {
    let node = root;
    for (let i = 0; i < d.path.length - 1; i++) {
      const k = d.path[i];
      if (!node[k] || typeof node[k] !== "object") node[k] = {};
      node = node[k] as Record<string, unknown>;
    }
    node[d.path[d.path.length - 1]] = leaf(d.value);
  }
  return root;
}

/** Plain stats doc (numbers only) built from scratch. Used by the backfill and the tests. */
export interface StatsDoc {
  total: number;
  active: number;
  s1InsuranceDocs: number;
  embassyHealthCerts: number;
  byCity: Record<string, Record<string, number>>;
  byCompany?: Record<string, {total: number; active: number}>;
}

export function emptyStats(withCompanies: boolean): StatsDoc {
  const s: StatsDoc = {total: 0, active: 0, s1InsuranceDocs: 0, embassyHealthCerts: 0, byCity: {}};
  if (withCompanies) s.byCompany = {};
  return s;
}

/** Adds deltas to a plain stats doc in place (what increment does on the server). */
export function applyDeltas(doc: Record<string, unknown>, deltas: Delta[]): void {
  for (const d of deltas) {
    let node = doc;
    for (let i = 0; i < d.path.length - 1; i++) {
      const k = d.path[i];
      if (!node[k] || typeof node[k] !== "object") node[k] = {};
      node = node[k] as Record<string, unknown>;
    }
    const last = d.path[d.path.length - 1];
    node[last] = (Number(node[last]) || 0) + d.value;
  }
}

/** Adds one delegate doc to a from-scratch stats doc. */
export function accumulate(doc: StatsDoc, data: Data, companyId: string | null): void {
  applyDeltas(doc as unknown as Record<string, unknown>, deltasFor(null, data, companyId));
}

/**
 * Drops zero leaves and empty maps so two docs that mean the same compare
 * equal (an increment that went back to 0 leaves a 0 on the server).
 */
export function normalizeStats(v: unknown): unknown {
  if (typeof v === "number") return v;
  if (!v || typeof v !== "object" || Array.isArray(v)) return undefined;
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(v as Record<string, unknown>).sort()) {
    const n = normalizeStats((v as Record<string, unknown>)[k]);
    if (n === undefined || n === 0) continue;
    if (typeof n === "object" && Object.keys(n as object).length === 0) continue;
    out[k] = n;
  }
  return out;
}

const COUNTED_KEYS = ["total", "active", "s1InsuranceDocs", "embassyHealthCerts", "byCity", "byCompany"];

/** Only the counted fields of a stored stats doc (drops updatedAt, ids, version). */
export function countedPart(data: Data): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!data) return out;
  for (const k of COUNTED_KEYS) if (k in data) out[k] = data[k];
  return out;
}

export function sameStats(a: Data, b: Data): boolean {
  return JSON.stringify(normalizeStats(countedPart(a))) === JSON.stringify(normalizeStats(countedPart(b)));
}

/**
 * Parses organizations/{orgId}/companies/{companyId}/delegates/{id}.
 * Returns null for any other delegates path (legacy top-level copies).
 */
export function parseDelegatePath(path: string): {orgId: string; companyId: string; delegateId: string} | null {
  const p = path.split("/");
  if (p.length !== 6 || p[0] !== "organizations" || p[2] !== "companies" || p[4] !== "delegates") return null;
  if (!p[1] || !p[3] || !p[5]) return null;
  return {orgId: p[1], companyId: p[3], delegateId: p[5]};
}
