/// Dev tashil-dev credentials for Patrol smoke (no secrets in repo).
///
/// Mac / CI must pass `--dart-define=PATROL_DEV_SECRET=…` (and optionally
/// phone / expected role label). Same account policy as [maestro/README.md].
class SmokeDevPatrolCredentials {
  const SmokeDevPatrolCredentials({
    required this.phone,
    required this.secret,
    this.nationalId = '',
    this.expectedRoleLabel = '',
  });

  /// Default staff supervisor dev phone ([docs/DEV_ENVIRONMENT.md]).
  static const String defaultStaffPhone = '01500000002';

  /// Default delegate dev phone ([docs/DEV_ENVIRONMENT.md]).
  static const String defaultDelegatePhone = '01500000003';

  /// Fake national ID for dev delegate login (documented in [docs/DEV_ENVIRONMENT.md]).
  static const String defaultDelegateNationalId = '29901015740919';

  @Deprecated('Use defaultStaffPhone')
  static const String defaultPhone = defaultStaffPhone;

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
  final String nationalId;
  final String expectedRoleLabel;

  bool get hasSecret => secret.isNotEmpty;

  bool get hasDelegateNationalId => nationalId.isNotEmpty;

  /// Staff supervisor account for Patrol setup (`01500000002`).
  static SmokeDevPatrolCredentials staffFromEnvironment() {
    const phone = String.fromEnvironment(
      'PATROL_DEV_PHONE',
      defaultValue: defaultStaffPhone,
    );
    const secret = String.fromEnvironment('PATROL_DEV_SECRET');
    const roleOverride = String.fromEnvironment('PATROL_DEV_ROLE_LABEL');
    final expectedRoleLabel = roleOverride.isNotEmpty
        ? roleOverride
        : expectedProfileRoleLabelForPatrolPhone(phone);
    return SmokeDevPatrolCredentials(
      phone: phone,
      secret: secret,
      nationalId: '',
      expectedRoleLabel: expectedRoleLabel,
    );
  }

  /// Dev delegate account for Patrol setup (`01500000003` + national ID).
  static SmokeDevPatrolCredentials delegateFromEnvironment() {
    const phone = String.fromEnvironment(
      'PATROL_DEV_PHONE',
      defaultValue: defaultDelegatePhone,
    );
    const nationalId = String.fromEnvironment(
      'PATROL_DEV_NATIONAL_ID',
      defaultValue: defaultDelegateNationalId,
    );
    return SmokeDevPatrolCredentials(
      phone: phone,
      secret: '',
      nationalId: nationalId,
      expectedRoleLabel: '',
    );
  }

  /// From `dart-define` / Patrol CLI (never hard-code passwords in git).
  static SmokeDevPatrolCredentials fromEnvironment() => staffFromEnvironment();
}
