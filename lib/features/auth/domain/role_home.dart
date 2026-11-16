import 'package:delegate_app/core/platform/web_runtime_policy.dart';
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

const String kWebHrSystemPath = '/hr/home';

/// Web only: company supervisors and HR get the HR desktop system and never
/// a mobile-style home. Every stored supervisor spelling (`supervisor`,
/// `company_supervisor`, `company-admin`, `company_admin`, `companyadmin`,
/// `admin`) resolves to [UserRole.admin], and every HR spelling to
/// [UserRole.hr]. The company is not an input, so a legacy account without a
/// `companyUID` still lands on the HR system (its screens scope by equality
/// on the company and show nothing from other companies).
bool usesWebHrSystem(UserRole role, {required bool isWeb}) =>
    isWeb && (role == UserRole.admin || role == UserRole.hr);

/// Route used right after sign-in and after the splash restores a session.
/// Mobile always gets [homePathForRole].
String landingPathForRole(UserRole role, {bool? isWeb}) =>
    usesWebHrSystem(role, isWeb: isWeb ?? WebRuntimePolicy.isWeb)
    ? kWebHrSystemPath
    : homePathForRole(role);

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

/// Who may open `/hr/home` and `/hr/delegate-attendance`.
///
/// Mobile sends only [UserRole.hr] here ([homePathForRole]). Company
/// supervisors are [UserRole.admin] for every stored spelling (`supervisor`,
/// `company_supervisor`, `company-admin`, `company_admin`, `companyadmin`,
/// `admin`); on mobile they open the individual HR screens from the admin
/// shell, and on web they land here. Super admin, technical support and
/// organization admin keep their own shells. No other role mounts the HR shell.
bool canOpenHrShell(UserRole role) =>
    role == UserRole.admin || role == UserRole.hr;

/// Null when [role] may stay on the HR shell. Web delegates go to the
/// login-screen notice. Everyone else goes to [homePathForRole].
String? hrShellDeniedLocation(UserRole role, {required bool isWeb}) {
  if (canOpenHrShell(role)) return null;
  if (isWeb && role == UserRole.delegate) return '/login?notice=delegate';
  return homePathForRole(role);
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
