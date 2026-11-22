/**
 * TAS-229: named penalty notifications for the managers of the penalty's
 * organization. The app used to look these users up itself, but company
 * staff (HR, supervisors) cannot read the organization's users under the
 * rules, so only the role broadcasts arrived. The server does it now.
 *
 * Who: users of the penalty's organization (organizationUID or
 * organizationUIDs) whose role is an organization admin, a super admin,
 * or (not for confidential penalties) a branches marketing manager.
 * Technical support only for confidential penalties.
 */

export type PenaltyDoc = Record<string, unknown>;

export interface ManagerUser {
  id: string;
  data: Record<string, unknown>;
}

export interface ManagerRecipient {
  uid: string;
  isBmm: boolean;
  phone: string;
}

const ORG_ADMIN = new Set([
  "organizationadmin", "organization-admin", "organization_admin",
]);
const SUPER_ADMIN = new Set(["superadmin", "super-admin", "super_admin"]);
const TECH_SUPPORT = new Set([
  "technicalsupport", "technical_support", "technical-support", "tech_support", "techsupport",
]);
const BRANCHES_MARKETING = new Set([
  "branchesmarketingmanager", "branches_marketing", "branches-marketing",
  "branches_marketing_manager",
]);

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/** Organization of a penalty (new field, then the legacy spelling). */
export function penaltyOrganizationId(p: PenaltyDoc): string {
  return str(p.organizationId) || str(p.organizationUID);
}

function inOrganization(data: Record<string, unknown>, org: string): boolean {
  if (str(data.organizationUID) === org) return true;
  const ids = data.organizationUIDs;
  return Array.isArray(ids) && ids.some((x) => str(x) === org);
}

/**
 * Managers to notify by name, de-duplicated, creator left out (they made it).
 */
export function penaltyManagerRecipients(
  users: ManagerUser[],
  penalty: PenaltyDoc,
): ManagerRecipient[] {
  const org = penaltyOrganizationId(penalty);
  if (!org) return [];
  const confidential = penalty.isConfidential === true;
  const creator = str(penalty.createdById);
  const seen = new Set<string>();
  const out: ManagerRecipient[] = [];
  for (const u of users) {
    if (!u.id || seen.has(u.id) || u.id === creator) continue;
    if (!inOrganization(u.data, org)) continue;
    const role = str(u.data.role).toLowerCase();
    const isBmm = BRANCHES_MARKETING.has(role);
    const ok = ORG_ADMIN.has(role) || SUPER_ADMIN.has(role) ||
      (confidential ? TECH_SUPPORT.has(role) : isBmm);
    if (!ok) continue;
    seen.add(u.id);
    out.push({uid: u.id, isBmm, phone: str(u.data.phoneNumber) || str(u.data.phone)});
  }
  return out;
}

/** Same wording the app used for these notifications. */
export function penaltyManagerMessage(
  penalty: PenaltyDoc,
  isBmm: boolean,
): {title: string; body: string} {
  const fine = Number(penalty.fineAmount) || 0;
  const fineStr = fine.toFixed(0);
  const branch = str(penalty.branchName) || "الفرع المحدد";
  const delegate = str(penalty.targetDelegateName) || "المندوب";
  const company = str(penalty.companyName);
  const title = str(penalty.title);
  if (isBmm) {
    const body = fine <= 1000 ?
      `تم تسجيل مخالفة (${title}) بمبلغ ${fineStr} ج.م على المندوب (${delegate}) بشركة (${company}) بفرع (${branch}). المخالفة ضمن صلاحية اعتمادك وإصدارك الفوري (≤ 1000 ج.م).` :
      `تم تسجيل مخالفة (${title}) بمبلغ ${fineStr} ج.م على المندوب (${delegate}) بشركة (${company}) بفرع (${branch}). المخالفة تتطلب مراجعتك وتمريرها للمدير العام (> 1000 ج.م).`;
    return {title: "مخالفة جديدة قيد مراجعتك واعتمادك", body};
  }
  if (penalty.isConfidential === true) {
    return {
      title: "إشعار تسجيل مخالفة سرية على النظام",
      body: `تم تسجيل مخالفة سرية (${title}) بمبلغ ${fineStr} ج.م على المندوب (${delegate}) بشركة (${company}).`,
    };
  }
  return {
    title: "إشعار تسجيل مخالفة جديدة على النظام",
    body: `تم تسجيل مخالفة (${title}) بمبلغ ${fineStr} ج.م على المندوب (${delegate}) بشركة (${company}) بفرع (${branch})، وهي الآن قيد المراجعة والاعتماد الأول من مدير تسويق الفروع.`,
  };
}

/** Deterministic id so a retried trigger does not notify twice. */
export function penaltyManagerNotificationId(penaltyId: string, uid: string): string {
  return `penalty_${penaltyId}_mgr_${uid}`;
}

/** Notification doc fields (createdAt is added by the caller). */
export function penaltyManagerNotification(
  penaltyId: string,
  penalty: PenaltyDoc,
  r: ManagerRecipient,
): Record<string, unknown> {
  const {title, body} = penaltyManagerMessage(penalty, r.isBmm);
  const doc: Record<string, unknown> = {
    title,
    body,
    type: "penalty",
    penaltyId,
    companyId: str(penalty.companyId),
    companyName: str(penalty.companyName),
    branchId: penalty.branchId ?? null,
    branchName: penalty.branchName ?? null,
    targetDelegateId: penalty.targetDelegateId ?? null,
    targetDelegateName: penalty.targetDelegateName ?? null,
    fineAmount: Number(penalty.fineAmount) || 0,
    category: penalty.category ?? null,
    incidentDescription: str(penalty.incidentDescription),
    createdById: str(penalty.createdById),
    createdByName: str(penalty.createdByName),
    senderName: str(penalty.createdByName),
    senderRole: "supervisor",
    delegateUid: r.uid,
    isRead: false,
    read: false,
    deletedBy: [],
  };
  if (r.phone) doc.phoneNumber = r.phone;
  return doc;
}
