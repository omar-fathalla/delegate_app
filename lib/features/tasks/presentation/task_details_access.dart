import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Roles that open [TaskDetailsScreen] as staff (edit/delete if they sent it).
/// Field delegates and branch marketing open it as recipients.
bool taskNotificationOpensAsAdmin(UserRole role) {
  switch (role) {
    case UserRole.admin:
    case UserRole.organizationAdmin:
    case UserRole.superAdmin:
    case UserRole.technicalSupport:
    case UserRole.branchesMarketingManager:
    case UserRole.marketingPromotion:
      return true;
    case UserRole.delegate:
    case UserRole.marketing:
    case UserRole.accountant:
    case UserRole.hr:
      return false;
  }
}
