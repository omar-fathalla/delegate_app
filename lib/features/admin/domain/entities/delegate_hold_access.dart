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
