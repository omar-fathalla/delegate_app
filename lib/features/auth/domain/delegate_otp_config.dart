import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Client gate for the delegate phone OTP step.
///
/// Default is off, including release builds, so current delegates keep
/// signing in with phone and national ID only. Turn it on for a local run
/// with:
///
/// ```sh
/// flutter run --dart-define=DELEGATE_OTP_ENABLED=true
/// ```
///
/// Tests assign [enabled] directly and restore it afterwards.
///
/// This flag is not proof of possession. `delegateLoginV2` still issues a
/// custom token before any SMS is sent, and Firestore rules do not read a
/// phone provider. A later change can set `phone_number` on that token
/// (or require `request.auth.token.phone_number` / the phone identity to
/// match the delegate) and refuse delegate reads until it does. Do not
/// treat a client-side OTP screen as that control.
abstract final class DelegateOtpConfig {
  static const bool defaultEnabled = bool.fromEnvironment(
    'DELEGATE_OTP_ENABLED',
    defaultValue: false,
  );

  static bool enabled = defaultEnabled;

  static const Duration resendCooldown = Duration(seconds: 60);
}

/// Staff email/password profiles are marked in [Delegate.nationalityID].
/// Delegate documents loaded after `delegateLoginV2` are not.
bool isStaffPasswordProfile(String nationalityId) {
  return nationalityId.startsWith('__firebase_auth__:') ||
      nationalityId.startsWith('__phone_auth__:');
}

/// OTP applies only to the custom-token delegate path, and only when
/// [DelegateOtpConfig.enabled] is on.
bool delegateLoginNeedsPhoneOtp(List<Delegate> delegates) {
  if (!DelegateOtpConfig.enabled || delegates.isEmpty) return false;
  return delegates.every(
    (delegate) => !isStaffPasswordProfile(delegate.nationalityID),
  );
}
