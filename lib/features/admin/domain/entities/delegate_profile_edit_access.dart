import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Who may open the mobile "edit delegate data" action and call
/// [editDelegateProfile]. Mirrors `canCallEditDelegateProfile` /
/// `profileEditCompanyScope` in functions/src/delegate_profile_edit_logic.ts.
///
/// Allowed: company admin / supervisor (same company, fail-closed on an
/// empty companyUID), super-admin, and technical support (global).
bool canShowEditDelegateProfile({
  required UserRole? role,
  required String callerCompanyUID,
  required String targetCompanyUID,
  required bool targetEditableStatus,
}) {
  if (role == null || !targetEditableStatus) return false;
  switch (role) {
    case UserRole.superAdmin:
    case UserRole.technicalSupport:
      return true;
    case UserRole.admin:
      final caller = callerCompanyUID.trim();
      final target = targetCompanyUID.trim();
      return caller.isNotEmpty && caller == target;
    case UserRole.organizationAdmin:
    case UserRole.hr:
    case UserRole.delegate:
    case UserRole.marketing:
    case UserRole.marketingPromotion:
    case UserRole.branchesMarketingManager:
    case UserRole.accountant:
      return false;
  }
}

/// Statuses the callable accepts for a live delegate profile.
bool isEditableDelegateProfileStatus(DelegateStatus status) {
  return status == DelegateStatus.active ||
      status == DelegateStatus.approved ||
      status == DelegateStatus.pending;
}
