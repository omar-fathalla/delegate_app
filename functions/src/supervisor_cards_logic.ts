/**
 * Pure helpers for getMySupervisorCards (TAS-55).
 *
 * User decision 2026-11-24: a delegate sees only its own delegate document.
 * From its company's supervisors it may see the name, phone, email and photo
 * (the supervisor card on the home screen), nothing else.
 */

export const SUPERVISOR_POSITIONS = ["supervisor", "Supervisor", "مشرف"];

export interface Denial {
  code: "unauthenticated" | "permission-denied" | "invalid-argument";
  reason: string;
  message: string;
}

export interface Scope {
  organizationUID: string;
  companyUID: string;
}

export interface SupervisorCard {
  uid: string;
  displayName: string;
  phoneNumber: string;
  email: string;
  photoUrl: string;
}

export function isDenial(v: unknown): v is Denial {
  return typeof v === "object" && v !== null && "reason" in v && "code" in v;
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function strList(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x) => typeof x === "string") as string[] : [];
}

/**
 * The company is the one in the request when the token covers it (orgId /
 * orgIds and companyId / companyIds claims), otherwise the token's own
 * orgId / companyId. Only delegate tokens may call this.
 */
export function parseScope(
  data: unknown,
  token: Record<string, unknown> | undefined,
): Scope | Denial {
  if (!token) {
    return {code: "unauthenticated", reason: "unauthenticated", message: "Sign in required."};
  }
  if (token.role !== "delegate") {
    return {code: "permission-denied", reason: "not_delegate", message: "Delegates only."};
  }
  const req = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const orgs = [str(token.orgId), ...strList(token.orgIds)].filter(Boolean);
  const cos = [str(token.companyId), ...strList(token.companyIds)].filter(Boolean);
  const org = str(req.organizationUID) || str(token.orgId);
  const co = str(req.companyUID) || str(token.companyId);
  if (!org || !co) {
    return {code: "invalid-argument", reason: "no_company", message: "No company in the request or token."};
  }
  if (!orgs.includes(org) || !cos.includes(co)) {
    return {code: "permission-denied", reason: "other_company", message: "Not your company."};
  }
  return {organizationUID: org, companyUID: co};
}

/** Same order as the app's _extractPersonName. */
export function personName(d: Record<string, unknown>): string {
  for (const k of ["fullName", "displayName", "name"]) {
    const v = str(d[k]);
    if (v) return v;
  }
  return `${str(d.firstName)} ${str(d.lastName)}`.trim();
}

function photoOf(d: Record<string, unknown>): string {
  for (const k of ["profileImageUrl", "profileImage", "personalPhotoURL", "personalPhotoUrl", "photoURL", "photoUrl", "avatarUrl"]) {
    const v = str(d[k]);
    if (v) return v;
  }
  return "";
}

/** Only the four allowed fields leave the server. */
export function toCard(uid: string, d: Record<string, unknown>): SupervisorCard {
  return {
    uid,
    displayName: personName(d),
    phoneNumber: str(d.phoneNumber) || str(d.phone),
    email: str(d.email),
    photoUrl: photoOf(d),
  };
}

/** Active supervisors only, own uid excluded, de-duplicated by phone. */
export function cardsFrom(
  callerUid: string,
  docs: Array<{id: string; data: Record<string, unknown>}>,
): SupervisorCard[] {
  const seen = new Set<string>();
  const out: SupervisorCard[] = [];
  for (const {id, data} of docs) {
    if (id === callerUid) continue;
    const status = str(data.status).toLowerCase();
    if (status && status !== "active") continue;
    const card = toCard(id, data);
    const key = card.phoneNumber || id;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(card);
  }
  return out;
}
