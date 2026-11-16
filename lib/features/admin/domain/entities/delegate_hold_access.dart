import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Who may call [setDelegateHold] for a target chain/company.
/// Mirrors `decideSetDelegateHold` in functions/src/holds.ts.
///
/// Allowed: super-admin, technical support, organization-admin (own org),
/// and company admin / company supervisor (UserRole.admin; own org + company,
/// fail-closed if companyUID is empty). HR and other roles are denied.
bool canSetDelegateHold({
  required UserRole? role,
  required String callerOrganizationUID,
  required String callerCompanyUID,
  required String targetOrganizationUID,
  required String targetCompanyUID,
}) {
  final targetOrg = targetOrganizationUID.trim();
  final targetCo = targetCompanyUID.trim();
  if (role == null || targetOrg.isEmpty || targetCo.isEmpty) return false;
  final callerOrg = callerOrganizationUID.trim();
  final callerCo = callerCompanyUID.trim();
  switch (role) {
    case UserRole.superAdmin:
    case UserRole.technicalSupport:
      return true;
    case UserRole.organizationAdmin:
      return callerOrg.isNotEmpty && callerOrg == targetOrg;
    case UserRole.admin:
      return callerOrg.isNotEmpty &&
          callerCo.isNotEmpty &&
          callerOrg == targetOrg &&
          callerCo == targetCo;
    case UserRole.delegate:
    case UserRole.marketing:
    case UserRole.marketingPromotion:
    case UserRole.branchesMarketingManager:
    case UserRole.accountant:
    case UserRole.hr:
      return false;
  }
}

/// Callable fields for `setDelegateHold`.
///
/// A company supervisor (`UserRole.admin`) may suspend only a delegate in
/// their own company, and the only mutation is the admin-suspend hold that
/// drives status. Profile fields are never included. Returns null when the
/// caller is out of scope, including an empty company UID.
const String companySupervisorStatusHold = 'admin_suspend';

const Set<String> delegateHoldPayloadKeys = {
  'uid',
  'orgId',
  'companyId',
  'hold',
  'op',
  'note',
};

Map<String, dynamic>? buildDelegateHoldPayload({
  required UserRole? callerRole,
  required String callerOrganizationUID,
  required String callerCompanyUID,
  required String uid,
  required String organizationUID,
  required String companyUID,
  required String op,
  String hold = companySupervisorStatusHold,
  String? note,
}) {
  if (callerRole == UserRole.admin && hold != companySupervisorStatusHold) {
    return null;
  }
  if (!canSetDelegateHold(
    role: callerRole,
    callerOrganizationUID: callerOrganizationUID,
    callerCompanyUID: callerCompanyUID,
    targetOrganizationUID: organizationUID,
    targetCompanyUID: companyUID,
  )) {
    return null;
  }
  final trimmedNote = note?.trim() ?? '';
  return {
    'uid': uid,
    'orgId': organizationUID,
    'companyId': companyUID,
    'hold': hold,
    'op': op,
    if (trimmedNote.isNotEmpty) 'note': trimmedNote,
  };
}
