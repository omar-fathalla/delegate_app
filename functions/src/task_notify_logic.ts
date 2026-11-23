/**
 * Recipients for a new (or newly assigned) task notification.
 *
 * The app stores `assignedTo` as a single string: a delegate uid, `all`
 * (جميع المناديب / «الكل»), `all_branch_marketing`, or
 * `all_marketing_promotion`. The previous trigger cast that string to
 * `string[]` and iterated characters, so group sends never reached the
 * intended people. Resolution is company-scoped and de-duplicated.
 */

import {canonicalStatus, hasAnyHold, parseHolds} from "./holds";

export const ASSIGN_ALL = "all";
export const ASSIGN_ALL_AR = "الكل";
export const ASSIGN_ALL_BRANCH_MARKETING = "all_branch_marketing";
export const ASSIGN_ALL_MARKETING_PROMOTION = "all_marketing_promotion";

const FIELD_DELEGATE_ROLES = new Set([
  "delegate",
]);

const BRANCH_MARKETING_ROLES = new Set([
  "marketing",
  "branches_marketing",
  "branches-marketing",
  "branchesmarketing",
  "branches_marketing_manager",
  "branches-marketing-manager",
  "branchesmarketingmanager",
]);

const MARKETING_PROMOTION_ROLES = new Set([
  "marketingPromotion",
  "marketing_promotion",
  "marketing-promotion",
  "marketingpromotion",
]);

/** Statuses that must not receive a new-task notification. */
const SKIP_STATUS = new Set([
  "pending",
  "rejected",
  "deleted",
  "disabled",
  "suspended",
  "inactive",
]);

/** Image access still grants held/suspended/inactive readers who are in the assignment set. */
const SKIP_STATUS_IMAGE = new Set([
  "pending",
  "rejected",
  "deleted",
  "disabled",
]);

export type TaskRecipientMode = "notify" | "image";

export type TaskUser = {
  id: string;
  role?: unknown;
  companyUID?: unknown;
  companyId?: unknown;
  companyIds?: unknown;
  organizationUID?: unknown;
  organizationUIDs?: unknown;
  status?: unknown;
  holds?: unknown;
};

export type TaskNotifyOpts = {
  companyId?: string;
  organizationId?: string;
  createdBy?: string;
};

export function canonicalizeRole(role: unknown): string {
  return String(role || "").trim().toLowerCase().replace(/_/g, "-");
}

function roleIn(role: unknown, rawSet: Set<string>): boolean {
  const raw = String(role || "").trim();
  if (!raw) return false;
  if (rawSet.has(raw)) return true;
  const canon = canonicalizeRole(role);
  for (const item of rawSet) {
    if (canonicalizeRole(item) === canon) return true;
  }
  return false;
}

export function isFieldDelegateRole(role: unknown): boolean {
  return roleIn(role, FIELD_DELEGATE_ROLES);
}

export function isBranchMarketingRole(role: unknown): boolean {
  return roleIn(role, BRANCH_MARKETING_ROLES);
}

export function isMarketingPromotionRole(role: unknown): boolean {
  return roleIn(role, MARKETING_PROMOTION_ROLES);
}

export function isAllAssignToken(value: string): boolean {
  const v = value.trim();
  return v === ASSIGN_ALL || v === ASSIGN_ALL_AR;
}

export function isGroupAssignToken(value: string): boolean {
  const v = value.trim();
  return isAllAssignToken(v) ||
    v === ASSIGN_ALL_BRANCH_MARKETING ||
    v === ASSIGN_ALL_MARKETING_PROMOTION;
}

function companyIdsOf(u: TaskUser): string[] {
  const ids: string[] = [];
  const primary = String(u.companyUID || u.companyId || "").trim();
  if (primary) ids.push(primary);
  const extra = u.companyIds;
  if (Array.isArray(extra)) {
    for (const v of extra) {
      const s = String(v || "").trim();
      if (s) ids.push(s);
    }
  }
  return ids;
}

function orgIdsOf(u: TaskUser): string[] {
  const ids: string[] = [];
  const primary = String(u.organizationUID || "").trim();
  if (primary) ids.push(primary);
  const extra = u.organizationUIDs;
  if (Array.isArray(extra)) {
    for (const v of extra) {
      const s = String(v || "").trim();
      if (s) ids.push(s);
    }
  }
  return ids;
}

export function userInCompany(u: TaskUser, companyId: string): boolean {
  const co = String(companyId || "").trim();
  if (!co) return false;
  return companyIdsOf(u).includes(co);
}

export function userInOrg(u: TaskUser, organizationId: string): boolean {
  const org = String(organizationId || "").trim();
  if (!org) return false;
  return orgIdsOf(u).includes(org);
}

/**
 * Exclude pending/rejected/deleted/disabled, and anyone the HOLDS model
 * treats as suspended (legacy status, or a non-empty holds object).
 * `approved` is canonicalized to `active` and is kept.
 */
export function isExcludedFromTaskNotify(u: TaskUser): boolean {
  if (hasAnyHold(parseHolds(u.holds))) return true;
  const s = canonicalStatus(u.status);
  return s !== "" && (SKIP_STATUS.has(s) || SKIP_STATUS.has(normalizeStatusRaw(u.status)));
}

function normalizeStatusRaw(status: unknown): string {
  return String(status || "").trim().toLowerCase();
}

function isSkippedStatus(u: TaskUser, mode: TaskRecipientMode = "notify"): boolean {
  if (mode === "image") {
    // Holds and suspended/inactive do not lose an existing image.
    const s = canonicalStatus(u.status);
    const raw = normalizeStatusRaw(u.status);
    return (s !== "" && SKIP_STATUS_IMAGE.has(s)) || SKIP_STATUS_IMAGE.has(raw);
  }
  return isExcludedFromTaskNotify(u);
}

export type ParsedAssignedTo =
  | {kind: "empty"}
  | {kind: "group"; token: string}
  | {kind: "uids"; uids: string[]}
  | {kind: "mixed"; tokens: string[]; uids: string[]};

/**
 * Parse the app's `assignedTo` field. A plain string is one token or one
 * uid — it is never split into characters.
 */
export function parseAssignedTo(assignedTo: unknown): ParsedAssignedTo {
  if (assignedTo == null) return {kind: "empty"};
  if (typeof assignedTo === "string") {
    const v = assignedTo.trim();
    if (!v) return {kind: "empty"};
    if (isGroupAssignToken(v)) return {kind: "group", token: isAllAssignToken(v) ? ASSIGN_ALL : v};
    return {kind: "uids", uids: [v]};
  }
  if (Array.isArray(assignedTo)) {
    const tokens: string[] = [];
    const uids: string[] = [];
    const seen = new Set<string>();
    for (const raw of assignedTo) {
      if (typeof raw !== "string") continue;
      const v = raw.trim();
      if (!v || seen.has(v)) continue;
      seen.add(v);
      if (isGroupAssignToken(v)) {
        tokens.push(isAllAssignToken(v) ? ASSIGN_ALL : v);
      } else {
        uids.push(v);
      }
    }
    if (tokens.length === 0 && uids.length === 0) return {kind: "empty"};
    if (tokens.length === 0) return {kind: "uids", uids};
    if (uids.length === 0 && tokens.length === 1) return {kind: "group", token: tokens[0]};
    return {kind: "mixed", tokens, uids};
  }
  return {kind: "empty"};
}

function isSectorStaffRole(role: unknown): boolean {
  return isBranchMarketingRole(role) || isMarketingPromotionRole(role);
}

/**
 * «الكل» / `all` is company-delegates only. Sector marketing/promo staff
 * are not included, even if they appear in a combined candidate list.
 */
function seesAllGroup(u: TaskUser, opts: TaskNotifyOpts): boolean {
  const co = String(opts.companyId || "").trim();
  if (!co) return false;
  if (!userInCompany(u, co)) return false;
  if (isSectorStaffRole(u.role)) return false;
  return isFieldDelegateRole(u.role);
}

// TAS-270 #6 (product decision 2026-11-23): a company task belongs to that
// company only. Org-level marketing / promotion (no company) get the
// org-level sector tasks (no companyId), not every company's tasks.
function seesSectorGroup(u: TaskUser, opts: TaskNotifyOpts): boolean {
  const co = String(opts.companyId || "").trim();
  if (co) return userInCompany(u, co);
  return userInOrg(u, opts.organizationId || "");
}

function seesBranchMarketingGroup(u: TaskUser, opts: TaskNotifyOpts): boolean {
  return isBranchMarketingRole(u.role) && seesSectorGroup(u, opts);
}

function seesMarketingPromotionGroup(u: TaskUser, opts: TaskNotifyOpts): boolean {
  return isMarketingPromotionRole(u.role) && seesSectorGroup(u, opts);
}

function matchesGroup(u: TaskUser, token: string, opts: TaskNotifyOpts): boolean {
  if (isAllAssignToken(token)) return seesAllGroup(u, opts);
  if (token === ASSIGN_ALL_BRANCH_MARKETING) return seesBranchMarketingGroup(u, opts);
  if (token === ASSIGN_ALL_MARKETING_PROMOTION) return seesMarketingPromotionGroup(u, opts);
  return false;
}

function explicitUidAllowed(
  u: TaskUser | undefined,
  uid: string,
  opts: TaskNotifyOpts,
  mode: TaskRecipientMode = "notify",
): boolean {
  const co = String(opts.companyId || "").trim();
  if (!u) {
    // The task names this uid; include it when we have no profile to check.
    return true;
  }
  if (isSkippedStatus(u, mode)) return false;
  if (co && !userInCompany(u, co)) return false;
  return true;
}

/**
 * Unique recipient uids for a task. Never treats a string assignedTo as
 * an array of characters. Group `all` requires a company id (fail closed).
 * The creator is never notified. Suspended/inactive/held and pending/rejected/deleted/disabled are skipped.
 */
export function taskNotifyUserIds(
  users: TaskUser[],
  assignedTo: unknown,
  opts: TaskNotifyOpts = {},
  mode: TaskRecipientMode = "notify",
): string[] {
  const createdBy = String(opts.createdBy || "").trim();
  const parsed = parseAssignedTo(assignedTo);
  if (parsed.kind === "empty") return [];

  const byId = new Map<string, TaskUser>();
  for (const u of users) {
    if (!u || !u.id) continue;
    if (!byId.has(u.id)) byId.set(u.id, u);
  }

  const out: string[] = [];
  const seen = new Set<string>();
  const add = (id: string) => {
    if (!id || seen.has(id) || id === createdBy) return;
    seen.add(id);
    out.push(id);
  };

  const tokens = parsed.kind === "group" ? [parsed.token] :
    parsed.kind === "mixed" ? parsed.tokens : [];
  const uids = parsed.kind === "uids" ? parsed.uids :
    parsed.kind === "mixed" ? parsed.uids : [];

  for (const token of tokens) {
    for (const u of byId.values()) {
      if (isSkippedStatus(u, mode)) continue;
      if (matchesGroup(u, token, opts)) add(u.id);
    }
  }

  for (const uid of uids) {
    if (explicitUidAllowed(byId.get(uid), uid, opts, mode)) add(uid);
  }

  return out;
}

/**
 * Recipients who gained the assignment (after minus before). Used by
 * onTaskUpdated so a change from one person to «الكل» notifies the group
 * once, without re-notifying people already on the task.
 */
export function newlyAssignedTaskUserIds(
  users: TaskUser[],
  beforeAssignedTo: unknown,
  afterAssignedTo: unknown,
  opts: TaskNotifyOpts = {},
): string[] {
  const before = new Set(taskNotifyUserIds(users, beforeAssignedTo, opts));
  return taskNotifyUserIds(users, afterAssignedTo, opts).filter((id) => !before.has(id));
}

function groupTokensOf(assignedTo: unknown): string[] {
  const parsed = parseAssignedTo(assignedTo);
  if (parsed.kind === "group") return [parsed.token];
  if (parsed.kind === "mixed") return parsed.tokens;
  return [];
}

function hasExplicitUids(assignedTo: unknown): boolean {
  const parsed = parseAssignedTo(assignedTo);
  return parsed.kind === "uids" || (parsed.kind === "mixed" && parsed.uids.length > 0);
}

/** Company delegates subcollection is the source for «الكل» and explicit uids. */
export function assignmentNeedsCompanyDelegates(assignedTo: unknown): boolean {
  const tokens = groupTokensOf(assignedTo);
  return hasExplicitUids(assignedTo) || tokens.some((t) => isAllAssignToken(t));
}

/** Users-collection sector staff is the source for sector tokens. */
export function assignmentNeedsSectorStaff(assignedTo: unknown): boolean {
  return groupTokensOf(assignedTo).some((t) =>
    t === ASSIGN_ALL_BRANCH_MARKETING || t === ASSIGN_ALL_MARKETING_PROMOTION);
}

function mergeTaskUsers(...lists: TaskUser[][]): TaskUser[] {
  const seen = new Map<string, TaskUser>();
  for (const list of lists) {
    for (const u of list) {
      if (!u || !u.id || seen.has(u.id)) continue;
      seen.set(u.id, u);
    }
  }
  return Array.from(seen.values());
}

/**
 * Resolve recipients from the two product sources: company delegates
 * for «الكل» / explicit uids, and users-collection sector staff for
 * `all_branch_marketing` / `all_marketing_promotion`.
 */
export function taskNotifyUserIdsFromSources(
  delegates: TaskUser[],
  sectorStaff: TaskUser[],
  assignedTo: unknown,
  opts: TaskNotifyOpts = {},
  mode: TaskRecipientMode = "notify",
): string[] {
  const lists: TaskUser[][] = [];
  if (assignmentNeedsCompanyDelegates(assignedTo)) lists.push(delegates);
  if (assignmentNeedsSectorStaff(assignedTo)) lists.push(sectorStaff);
  return taskNotifyUserIds(mergeTaskUsers(...lists), assignedTo, opts, mode);
}

/** Same assignment set as notifications, but held/suspended readers stay. */
export function taskImageReaderIdsFromSources(
  delegates: TaskUser[],
  sectorStaff: TaskUser[],
  assignedTo: unknown,
  opts: TaskNotifyOpts = {},
): string[] {
  return taskNotifyUserIdsFromSources(delegates, sectorStaff, assignedTo, opts, "image");
}

export function newlyAssignedTaskUserIdsFromSources(
  delegates: TaskUser[],
  sectorStaff: TaskUser[],
  beforeAssignedTo: unknown,
  afterAssignedTo: unknown,
  opts: TaskNotifyOpts = {},
): string[] {
  const before = new Set(taskNotifyUserIdsFromSources(
    delegates, sectorStaff, beforeAssignedTo, opts));
  return taskNotifyUserIdsFromSources(
    delegates, sectorStaff, afterAssignedTo, opts,
  ).filter((id) => !before.has(id));
}


export type DelegateDocLike = {id: string; data: Record<string, unknown>};

/**
 * Map `organizations/{org}/companies/{companyUID}/delegates` docs to
 * [TaskUser]s. Dedupes by uid, skips docs with no uid. The resolved uid is
 * `data.uid` when present, otherwise the document id (same as the picker).
 */
export function taskUsersFromDelegateDocs(docs: DelegateDocLike[]): TaskUser[] {
  const seen = new Map<string, TaskUser>();
  for (const doc of docs) {
    if (!doc) continue;
    const data = doc.data || {};
    const fromField = String(data.uid || "").trim();
    const fromId = String(doc.id || "").trim();
    const id = fromField || fromId;
    if (!id) continue;
    if (seen.has(id)) continue;
    seen.set(id, {
      id,
      role: data.role,
      companyUID: data.companyUID,
      companyId: data.companyId,
      companyIds: data.companyIds,
      organizationUID: data.organizationUID,
      organizationUIDs: data.organizationUIDs,
      status: data.status,
      holds: data.holds,
    });
  }
  return Array.from(seen.values());
}
