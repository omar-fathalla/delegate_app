/**
 * Pure helpers that tell a real delegate link doc from a "ghost".
 *
 * A ghost is organizations/{org}/companies/{company}/delegates/{id} that only
 * holds device or backfill fields (boundDevice*, deviceBoundAt, position,
 * delegatePublicId ...). Old app builds (1.11 device_binding_service) wrote
 * the bound device with set(merge: true) on the delegate path, which creates
 * the doc again after the delegate was deleted. These helpers are shared by
 * delegateLoginV2 and the delete cleanup trigger.
 */

export const DELEGATE_NAME_FIELDS = ["fullName", "firstName", "middleName", "lastName", "name"];
export const DELEGATE_NATIONAL_ID_FIELDS = [
  "nationalityID", "nationalityId", "nationalId", "nationalID", "national_id", "idNumber",
];
export const DELEGATE_PHONE_FIELDS = ["phoneNumber", "phone", "mobile", "mobileNumber"];

/** Statuses that mean the delegate was removed. Login gets account_deleted. */
export const DELETED_DELEGATE_STATUSES = new Set(["deleted", "removed", "archived"]);

function filled(value: unknown): boolean {
  if (typeof value === "string") return value.trim().length > 0;
  if (typeof value === "number") return Number.isFinite(value);
  return false;
}

function anyFilled(data: Record<string, unknown>, fields: string[]): boolean {
  return fields.some((field) => filled(data[field]));
}

/** True when the doc has a name, a national ID or a phone number. */
export function hasDelegateIdentity(data: unknown): boolean {
  if (!data || typeof data !== "object") return false;
  const record = data as Record<string, unknown>;
  return anyFilled(record, DELEGATE_NAME_FIELDS)
    || anyFilled(record, DELEGATE_NATIONAL_ID_FIELDS)
    || anyFilled(record, DELEGATE_PHONE_FIELDS);
}

export function isDeletedDelegateStatus(status: unknown): boolean {
  if (status == null) return false;
  return DELETED_DELEGATE_STATUSES.has(String(status).trim().toLowerCase());
}

/** Roles on users/{uid} that belong to a delegate, not to a staff account. */
const DELEGATE_USER_ROLES = new Set(["", "delegate", "promoter"]);

export interface DeletedLinkCleanupInput {
  /** Other delegate link docs with the same id that still exist and have identity. */
  remainingLiveLinks: number;
  /** users/{id}.role, or null when there is no users doc. */
  usersRole: string | null;
}

export interface DeletedLinkCleanupPlan {
  clearDeviceBinding: boolean;
  cancelUnbindRequests: boolean;
  revokeSessions: boolean;
  /** TAS-217: delete users/{id} (only when it exists with a delegate role). */
  deleteUsersDoc: boolean;
  reason: "still_linked" | "staff_account" | "no_links_left";
}

/**
 * What to clear after a delegate link doc is deleted.
 * - Still linked in another company/chain: nothing, the delegate stays valid.
 * - The id is a staff account (company-admin etc. whose uid got a ghost doc
 *   from the old app): never revoke, that would sign the staff member out of
 *   the HR web.
 * - Otherwise: drop the server device binding, close open unbind requests,
 *   revoke the delegate's Firebase sessions so the next call needs a new login,
 *   and delete users/{id} when it is a delegate doc (TAS-217: the app could
 *   not delete it for tech support, so it stayed orphaned).
 */
export function planDeletedLinkCleanup(input: DeletedLinkCleanupInput): DeletedLinkCleanupPlan {
  if (input.remainingLiveLinks > 0) {
    return {clearDeviceBinding: false, cancelUnbindRequests: false, revokeSessions: false, deleteUsersDoc: false, reason: "still_linked"};
  }
  const role = (input.usersRole ?? "").trim().toLowerCase();
  if (input.usersRole !== null && !DELEGATE_USER_ROLES.has(role)) {
    return {clearDeviceBinding: false, cancelUnbindRequests: false, revokeSessions: false, deleteUsersDoc: false, reason: "staff_account"};
  }
  return {
    clearDeviceBinding: true, cancelUnbindRequests: true, revokeSessions: true,
    deleteUsersDoc: input.usersRole !== null, reason: "no_links_left",
  };
}
