import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Post-login route for a role. Company UID is not an input: accounts with
/// an empty company still land on the same home and must not crash there.
String homePathForRole(UserRole role) {
  switch (role) {
    case UserRole.superAdmin:
    case UserRole.admin:
    case UserRole.organizationAdmin:
    case UserRole.technicalSupport:
    case UserRole.branchesMarketingManager:
      return '/admin/home';
    case UserRole.accountant:
      return '/accountant/home';
    case UserRole.hr:
      return '/hr/home';
    case UserRole.marketing:
    case UserRole.marketingPromotion:
      return '/marketing/home';
    case UserRole.delegate:
      return '/home';
  }
}

/// Which shell [AdminMainScreen] mounts. Roles that do not use that screen
/// still map to [companySupervisor] so a stray navigation keeps the previous
/// fallback (the company supervisor tabs) instead of throwing.
enum AdminShellKind {
  superAdmin,
  technicalSupport,
  branchesMarketingManager,
  organizationAdmin,
  companySupervisor,
}

AdminShellKind adminShellKindFor(UserRole role) {
  switch (role) {
    case UserRole.superAdmin:
      return AdminShellKind.superAdmin;
    case UserRole.technicalSupport:
      return AdminShellKind.technicalSupport;
    case UserRole.branchesMarketingManager:
      return AdminShellKind.branchesMarketingManager;
    case UserRole.organizationAdmin:
      return AdminShellKind.organizationAdmin;
    case UserRole.admin:
    case UserRole.hr:
    case UserRole.delegate:
    case UserRole.marketing:
    case UserRole.marketingPromotion:
    case UserRole.accountant:
      return AdminShellKind.companySupervisor;
  }
}
