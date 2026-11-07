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

  /// Role badge on profile for supervisor @ `01500000002`.
  static const String defaultSupervisorRoleLabel = 'مشرف (Supervisor)';

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
    const roleLabel = String.fromEnvironment(
      'PATROL_DEV_ROLE_LABEL',
      defaultValue: defaultSupervisorRoleLabel,
    );
    return SmokeDevPatrolCredentials(
      phone: phone,
      secret: secret,
      expectedRoleLabel: roleLabel,
    );
  }
}
