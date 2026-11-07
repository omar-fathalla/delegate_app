/// Dev tashil-dev credentials for Patrol smoke (no secrets in repo).
///
/// Mac / CI must pass `--dart-define=PATROL_DEV_SECRET=…` (and optionally
/// phone / expected role label). Same account policy as [maestro/README.md].
class SmokeDevPatrolCredentials {
  const SmokeDevPatrolCredentials({
    required this.phone,
    required this.secret,
    required this.expectedRoleLabel,
  });

  /// Default supervisor dev phone ([docs/DEV_ENVIRONMENT.md]).
  static const String defaultPhone = '01500000002';

  /// Profile header badge for dev **staff** supervisor @ [defaultPhone].
  ///
  /// Auth maps Firestore `role: supervisor` to [UserRole.admin] with
  /// [DelegatePosition.supervisor] (`auth_remote_data_source` staff model).
  /// `UserProfileScreen._getRoleDisplayName` evaluates `UserRole.admin`
  /// before `DelegatePosition.supervisor`, so the badge is company admin text.
  static const String staffSupervisorProfileRoleLabel =
      'مشرف الشركة (Company Admin)';

  /// Resolves the profile role badge for known tashil-dev Patrol accounts.
  static String expectedProfileRoleLabelForPatrolPhone(String phone) {
    switch (phone) {
      case defaultPhone:
        return staffSupervisorProfileRoleLabel;
      default:
        throw ArgumentError(
          'Unknown PATROL_DEV_PHONE $phone — set PATROL_DEV_ROLE_LABEL explicitly.',
        );
    }
  }

  final String phone;
  final String secret;
  final String expectedRoleLabel;

  bool get hasSecret => secret.isNotEmpty;

  /// From `dart-define` / Patrol CLI (never hard-code passwords in git).
  static SmokeDevPatrolCredentials fromEnvironment() {
    const phone = String.fromEnvironment(
      'PATROL_DEV_PHONE',
      defaultValue: defaultPhone,
    );
    const secret = String.fromEnvironment('PATROL_DEV_SECRET');
    const roleOverride = String.fromEnvironment('PATROL_DEV_ROLE_LABEL');
    final expectedRoleLabel = roleOverride.isNotEmpty
        ? roleOverride
        : expectedProfileRoleLabelForPatrolPhone(phone);
    return SmokeDevPatrolCredentials(
      phone: phone,
      secret: secret,
      expectedRoleLabel: expectedRoleLabel,
    );
  }
}
