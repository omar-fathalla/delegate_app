/// Centralized application configuration.
///
/// Admin credentials and other sensitive values are loaded from
/// environment variables at build time via `--dart-define`.
///
/// Example build command:
/// ```
/// flutter run --dart-define=ADMIN_PHONE=01234567890 --dart-define=ADMIN_PASSWORD=mySecretPass
/// ```
///
/// For CI/CD, pass these values as secrets in your pipeline.
class AppConfig {
  AppConfig._();

  /// Admin phone number — passed via `--dart-define=ADMIN_PHONE=...`
  static const String adminPhone = String.fromEnvironment(
    'ADMIN_PHONE',
    defaultValue: '',
  );

  /// Admin password — passed via `--dart-define=ADMIN_PASSWORD=...`
  static const String adminPassword = String.fromEnvironment(
    'ADMIN_PASSWORD',
    defaultValue: '',
  );

  /// Whether admin credentials are configured.
  static bool get isAdminConfigured =>
      adminPhone.isNotEmpty && adminPassword.isNotEmpty;
}
