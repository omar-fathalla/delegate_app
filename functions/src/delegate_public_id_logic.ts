/**
 * One delegatePublicId per delegate (TAS-246, rule from Mohamed 22 Nov 2026):
 * a delegate keeps ONE code (DEL-n) whatever the number of chains.
 *
 * The canonical code is the oldest (lowest number) code found on any of the
 * delegate's copies or on users/{uid}. When there is no code anywhere and the
 * delegate is active, a new one is allocated from counters/delegates.
 */

export type Data = Record<string, unknown>;

const str = (v: unknown): string => (typeof v === "string" ? v.trim() : "");

/** The number in "DEL-6389" (6389), or null for anything that is not a code. */
export function publicIdNumber(code: unknown): number | null {
  const m = /^DEL-(\d+)$/i.exec(str(code));
  return m ? Number(m[1]) : null;
}

/** The oldest valid code among [codes], or "" when there is none. */
export function canonicalPublicId(codes: unknown[]): string {
  let best = "";
  let bestN = Infinity;
  for (const c of codes) {
    const n = publicIdNumber(c);
    if (n !== null && n < bestN) {
      bestN = n;
      best = str(c);
    }
  }
  return best;
}

export function formatPublicId(n: number): string {
  return `DEL-${String(n).padStart(4, "0")}`;
}

const ACTIVE = new Set(["active", "approved"]);

/** A real delegate copy (not a device-binding stub). */
export function isRealDelegateDoc(d: Data | null): boolean {
  return !!d && (str(d.uid) !== "" || str(d.fullName) !== "");
}

/** True when a delegate copy write should check the code. */
export function publicIdCheckNeeded(before: Data | null, after: Data | null): boolean {
  if (!after || !isRealDelegateDoc(after)) return false;
  if (!before) return true;
  const st = (d: Data) => str(d.status).toLowerCase();
  return str(before.delegatePublicId) !== str(after.delegatePublicId) ||
    (st(before) !== st(after) && ACTIVE.has(st(after)));
}

export interface PublicIdPlan {
  /** The code every doc must hold; "" means allocate a new one. */
  canonical: string;
  /** Allocate a new code (no code anywhere, delegate active). */
  allocate: boolean;
  /** Paths whose delegatePublicId must be set to the canonical code. */
  paths: string[];
}

/**
 * [copies]: every organizations/../delegates/{uid} doc of one delegate.
 * [user]: users/{uid} (path + data) or null.
 */
export function planPublicId(
  copies: Array<{path: string; data: Data}>,
  user: {path: string; data: Data} | null,
): PublicIdPlan {
  const real = copies.filter((c) => isRealDelegateDoc(c.data));
  const all = user ? [...real, user] : real;
  const canonical = canonicalPublicId(all.map((d) => d.data.delegatePublicId));
  if (!canonical) {
    const active = real.some((c) => ACTIVE.has(str(c.data.status).toLowerCase()));
    return {canonical: "", allocate: active && real.length > 0, paths: active ? all.map((d) => d.path) : []};
  }
  return {
    canonical,
    allocate: false,
    paths: all.filter((d) => str(d.data.delegatePublicId) !== canonical).map((d) => d.path),
  };
}

/**
 * True when a users/{uid} write should check the code. The app writes the
 * users doc after the copies, so an old app build can put a fresh code there.
 */
export function userPublicIdCheckNeeded(before: Data | null, after: Data | null): boolean {
  if (!after) return false;
  const code = str(after.delegatePublicId);
  if (!code) return false;
  return !before || str(before.delegatePublicId) !== code;
}
