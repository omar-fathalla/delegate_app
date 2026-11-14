import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
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

/// Whether a company editor may open [EditDelegateProfileScreen] for a pending
/// subscription request (not national-ID workflow or other excluded types).
bool canSupervisorEditSubscriptionRequest(
  DelegateSubscriptionRequest request, {
  required UserRole? role,
  required String callerCompanyUID,
}) {
  if (!canShowEditDelegateProfile(
    role: role,
    callerCompanyUID: callerCompanyUID,
    targetCompanyUID: request.companyUID,
    targetEditableStatus: request.status == SubscriptionRequestStatus.pending,
  )) {
    return false;
  }
  if (request.requestType == 'delete_delegate' ||
      request.isRenewalRequest ||
      request.requestType == 'add_organization' ||
      request.isNationalIdUpdateRequest) {
    return false;
  }
  return true;
}
