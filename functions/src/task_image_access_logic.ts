/**
 * Pure helpers for Phase 2 task-image access. A task image is readable
 * only by the sender (createdBy) and the intended recipients (the same
 * set resolved for new-task notifications). Other companies and
 * unrelated roles are denied. No I/O.
 */
import {parseTaskProofPath} from "./task_proof_access_logic";

export type ParsedTaskImagePath =
  | {
    kind: "new";
    companyUID: string;
    uploaderUid: string;
    fileName: string;
  }
  | {
    kind: "legacy";
    organizationId: string;
    uploaderUid: string;
    fileName: string;
  };

export function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Escape a uid so it can be used in a RegExp. */
export function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * N1-r: exact `task_{uid}_{token}` where token has no underscore
 * (optional file extension).
 */
export function isOwnedTaskImageFileName(fileName: string, uid: string): boolean {
  const id = str(uid);
  const name = str(fileName);
  if (!id || !name) return false;
  return new RegExp(
    `^task_${escapeRegExp(id)}_[^_]+(\\.[A-Za-z0-9]+)?$`,
  ).test(name);
}

export function fileNameFromImagePath(imagePath: string): string {
  const p = str(imagePath).replace(/\\/g, "/");
  const i = p.lastIndexOf("/");
  return i >= 0 ? p.slice(i + 1) : p;
}

/**
 * New uploads: task_images/{companyUID}/{uploaderUid}/task_{uid}_{token}.jpg
 * Legacy (Phase 1 and earlier): organizations/{orgId}/task_images/{uploaderUid}/{file}
 */
export function parseTaskImagePath(imagePath: unknown): ParsedTaskImagePath | null {
  const p = str(imagePath).replace(/\\/g, "/").replace(/^\/+/, "");
  if (!p || p.includes("..")) return null;
  const neu = /^task_images\/([^/]+)\/([^/]+)\/([^/]+)$/.exec(p);
  if (neu) {
    const companyUID = neu[1];
    const uploaderUid = neu[2];
    const fileName = neu[3];
    if (!companyUID || !uploaderUid || !isOwnedTaskImageFileName(fileName, uploaderUid)) {
      return null;
    }
    return {kind: "new", companyUID, uploaderUid, fileName};
  }
  const legacy = /^organizations\/([^/]+)\/task_images\/([^/]+)\/([^/]+)$/.exec(p);
  if (legacy) {
    const organizationId = legacy[1];
    const uploaderUid = legacy[2];
    const fileName = legacy[3];
    if (!organizationId || !uploaderUid || !fileName) return null;
    return {kind: "legacy", organizationId, uploaderUid, fileName};
  }
  return null;
}

export const MAX_TASK_IMAGES = 3;

export function normalizeTaskImagePath(path: unknown): string {
  return str(path).replace(/\\/g, "/").replace(/^\/+/, "");
}

/**
 * Prefer the Phase 3 `imagePaths` list; fall back to the legacy single
 * `imagePath` so one-image tasks keep working.
 */
export function taskImagePathsFromTask(task: {
  imagePath?: unknown;
  imagePaths?: unknown;
}): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (value: unknown) => {
    const path = normalizeTaskImagePath(value);
    if (!path || seen.has(path)) return;
    seen.add(path);
    out.push(path);
  };
  if (Array.isArray(task.imagePaths)) {
    for (const value of task.imagePaths) add(value);
  }
  if (out.length === 0) add(task.imagePath);
  return out.slice(0, MAX_TASK_IMAGES);
}

function taskImagePathMatchesTask(
  requestedPath: unknown,
  taskImagePath: unknown,
  taskImagePaths?: readonly unknown[] | null,
): boolean {
  const a = normalizeTaskImagePath(requestedPath);
  if (!a) return false;
  const list = (taskImagePaths != null && taskImagePaths.length > 0)
    ? taskImagePaths.map(normalizeTaskImagePath).filter(Boolean)
    : [normalizeTaskImagePath(taskImagePath)].filter(Boolean);
  return list.includes(a);
}

export function canReadTaskImage(input: {
  callerUid: unknown;
  createdBy: unknown;
  recipientIds: readonly string[];
  requestedPath: unknown;
  taskImagePath: unknown;
  taskImagePaths?: readonly unknown[] | null;
  taskCompanyId: unknown;
}): {ok: true} | {ok: false; reason: string} {
  const caller = str(input.callerUid);
  if (!caller) return {ok: false, reason: "sign_in_required"};
  if (!taskImagePathMatchesTask(
    input.requestedPath,
    input.taskImagePath,
    input.taskImagePaths,
  )) {
    return {ok: false, reason: "path_mismatch"};
  }
  const parsed = parseTaskImagePath(input.requestedPath);
  if (!parsed) return {ok: false, reason: "invalid_path"};
  if (parsed.kind === "new") {
    const co = str(input.taskCompanyId);
    if (!co || parsed.companyUID !== co) return {ok: false, reason: "company_mismatch"};
  }
  const sender = str(input.createdBy);
  if (caller === sender) return {ok: true};
  if (input.recipientIds.includes(caller)) return {ok: true};
  return {ok: false, reason: "not_allowed"};
}

/**
 * Uploader may preview their own new-path object before a task exists.
 * Recipients cannot use this path; they must go through a task check.
 */
export function canPreviewUnsentTaskImage(input: {
  callerUid: unknown;
  requestedPath: unknown;
}): {ok: true} | {ok: false; reason: string} {
  const caller = str(input.callerUid);
  if (!caller) return {ok: false, reason: "sign_in_required"};
  const parsed = parseTaskImagePath(input.requestedPath);
  if (!parsed || parsed.kind !== "new") return {ok: false, reason: "invalid_path"};
  if (parsed.uploaderUid !== caller) return {ok: false, reason: "not_allowed"};
  return {ok: true};
}

export function grantReaderUids(createdBy: unknown, recipientIds: readonly string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  const sender = str(createdBy);
  if (sender) {
    seen.add(sender);
    out.push(sender);
  }
  for (const raw of recipientIds) {
    const id = str(raw);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

export function shouldStripTaskImageDownloadToken(objectName: unknown): boolean {
  return parseTaskImagePath(objectName) != null
    || parseTaskProofPath(objectName) != null;
}

export type TaskImageGrantView = {
  imagePath?: unknown;
  createdBy?: unknown;
  readerUids?: unknown;
  companyUID?: unknown;
};

/**
 * Prefer the send-time grant (held/suspended users stay if they were
 * already readers). Fall back to a live assignment set that also keeps
 * held/suspended recipients. Never treats a missing imageUrl as a denial.
 */
export function decideAuthorizedTaskImageRead(input: {
  callerUid: unknown;
  requestedPath: unknown;
  taskImagePath: unknown;
  taskImagePaths?: readonly unknown[] | null;
  taskCompanyId: unknown;
  createdBy: unknown;
  grant?: TaskImageGrantView | null;
  fallbackRecipientIds: readonly string[];
}): {ok: true} | {ok: false; reason: string} {
  const resolved = taskImagePathsFromTask({
    imagePath: input.taskImagePath,
    imagePaths: input.taskImagePaths,
  });
  const requested = normalizeTaskImagePath(input.requestedPath);
  const grant = input.grant;
  const grantPath = grant ? normalizeTaskImagePath(grant.imagePath) : "";
  const useGrant = !!(grant && grantPath && grantPath === requested);
  const readerIds = useGrant
    ? (Array.isArray(grant!.readerUids) ? grant!.readerUids.map((v) => str(v)).filter(Boolean) : [])
    : input.fallbackRecipientIds;
  const createdBy = useGrant && str(grant!.createdBy) ? grant!.createdBy : input.createdBy;
  const company = useGrant && str(grant!.companyUID) ? grant!.companyUID : input.taskCompanyId;
  return canReadTaskImage({
    callerUid: input.callerUid,
    createdBy,
    recipientIds: readerIds,
    requestedPath: input.requestedPath,
    taskImagePath: resolved[0] || input.taskImagePath,
    taskImagePaths: resolved,
    taskCompanyId: company,
  });
}

