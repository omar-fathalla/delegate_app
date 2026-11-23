import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/domain/mfa_required_failure.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// TOTP two-step verification on Identity Platform (TAS-207).
///
/// Only TOTP is enrolled from the app. SMS second factors are not supported.

/// Builds the assertion that proves the TOTP code for [enrollmentId].
/// Tests pass a fake; production uses [TotpMultiFactorGenerator].
typedef TotpSignInAssertion =
    Future<MultiFactorAssertion> Function(String enrollmentId, String code);

Future<MultiFactorAssertion> defaultTotpSignInAssertion(
  String enrollmentId,
  String code,
) => TotpMultiFactorGenerator.getAssertionForSignIn(enrollmentId, code);

const String totpFactorId = 'totp';

const String mfaUnsupportedCode = 'mfa_unsupported';
const String mfaUnsupportedMessage =
    'هذا الحساب مفعّل عليه تحقق بخطوتين بطريقة غير مدعومة في التطبيق. '
    'يرجى التواصل مع الدعم الفني.';

const String totpInvalidCodeMessage =
    'رمز التحقق غير صحيح. تأكد من الرمز الحالي في تطبيق المصادقة وحاول مرة أخرى.';
const String totpSessionExpiredMessage =
    'انتهت مهلة التحقق. ارجع وأدخل كلمة المرور من جديد.';
const String totpRecentLoginMessage =
    'لأمان حسابك، سجّل الخروج ثم ادخل من جديد، وبعدها فعّل التحقق بخطوتين.';
const String totpGenericMessage =
    'تعذر التحقق من الرمز حالياً. تأكد من الاتصال بالإنترنت وحاول مرة أخرى.';

/// Arabic message for a Firebase Auth error raised while checking a TOTP
/// code or enrolling one.
String totpErrorMessage(String code) {
  switch (code) {
    case 'invalid-verification-code':
    case 'invalid-mfa-code':
    case 'invalid-code':
    case 'missing-code':
    case 'totp-challenge-timeout':
      return totpInvalidCodeMessage;
    case 'session-expired':
    case 'invalid-multi-factor-session':
    case 'missing-multi-factor-session':
    case 'code-expired':
      return totpSessionExpiredMessage;
    case 'requires-recent-login':
      return totpRecentLoginMessage;
    default:
      return totpGenericMessage;
  }
}

/// Stable failure code for [totpErrorMessage].
String totpErrorCode(String code) {
  final message = totpErrorMessage(code);
  if (message == totpInvalidCodeMessage) return 'invalid_mfa_code';
  if (message == totpSessionExpiredMessage) return 'mfa_session_expired';
  if (message == totpRecentLoginMessage) return 'requires_recent_login';
  return 'mfa_failed';
}

AuthFailure totpFailure(FirebaseAuthException error) =>
    AuthFailure(totpErrorMessage(error.code), totpErrorCode(error.code));

/// The enrolled TOTP factor among [hints], or null when the account only
/// has factors the app cannot answer (SMS).
MultiFactorInfo? totpHint(List<MultiFactorInfo> hints) {
  for (final hint in hints) {
    if (hint.factorId == totpFactorId) return hint;
  }
  return null;
}

/// Finishes [resolver]'s sign-in with [code]. Throws [AuthFailure] with an
/// Arabic message on a wrong or expired code.
Future<UserCredential> resolveTotpSignIn(
  MultiFactorResolver resolver,
  String code, {
  TotpSignInAssertion assertionFor = defaultTotpSignInAssertion,
}) async {
  final hint = totpHint(resolver.hints);
  if (hint == null) {
    throw const AuthFailure(mfaUnsupportedMessage, mfaUnsupportedCode);
  }
  try {
    final assertion = await assertionFor(hint.uid, code.trim());
    return await resolver.resolveSignIn(assertion);
  } on FirebaseAuthException catch (error) {
    throw totpFailure(error);
  }
}

/// Maps a password sign-in that needs a second factor to the domain
/// failure the login flow understands.
AuthFailure mfaFailureFromResolver(
  MultiFactorResolver resolver, {
  TotpSignInAssertion assertionFor = defaultTotpSignInAssertion,
}) {
  if (totpHint(resolver.hints) == null) {
    return const AuthFailure(mfaUnsupportedMessage, mfaUnsupportedCode);
  }
  return MfaRequiredFailure(
    resolve: (code) async {
      await resolveTotpSignIn(resolver, code, assertionFor: assertionFor);
    },
  );
}

/// What the enrollment sheet shows while the user scans the QR code.
class TotpEnrollmentStart {
  const TotpEnrollmentStart({required this.secretKey, required this.qrCodeUrl});

  /// Base32 key the user can type into the authenticator app.
  final String secretKey;

  /// `otpauth://` URL rendered as a QR code.
  final String qrCodeUrl;
}

/// Enrolls the signed-in user in TOTP. The sheet talks to this, so widget
/// tests use a fake and never reach Firebase.
abstract class TotpEnrollmentClient {
  /// True when the user already has a second factor.
  Future<bool> isEnrolled();

  /// Creates a new TOTP secret. Throws [AuthFailure].
  Future<TotpEnrollmentStart> start();

  /// Confirms [code] against the secret from [start] and enrolls it.
  /// Throws [AuthFailure].
  Future<void> finish(String code);
}

class FirebaseTotpEnrollmentClient implements TotpEnrollmentClient {
  FirebaseTotpEnrollmentClient(this.auth, {this.issuer = 'Tashil'});

  final FirebaseAuth auth;
  final String issuer;
  TotpSecret? _secret;

  User get _user {
    final user = auth.currentUser;
    if (user == null) {
      throw const AuthFailure(totpRecentLoginMessage, 'requires_recent_login');
    }
    return user;
  }

  @override
  Future<bool> isEnrolled() async {
    final factors = await _user.multiFactor.getEnrolledFactors();
    return factors.isNotEmpty;
  }

  @override
  Future<TotpEnrollmentStart> start() async {
    final user = _user;
    try {
      final session = await user.multiFactor.getSession();
      final secret = await TotpMultiFactorGenerator.generateSecret(session);
      _secret = secret;
      final account = (user.email ?? user.phoneNumber ?? user.uid).trim();
      final url = await secret.generateQrCodeUrl(
        accountName: account,
        issuer: issuer,
      );
      return TotpEnrollmentStart(secretKey: secret.secretKey, qrCodeUrl: url);
    } on FirebaseAuthException catch (error) {
      throw totpFailure(error);
    }
  }

  @override
  Future<void> finish(String code) async {
    final secret = _secret;
    if (secret == null) {
      throw const AuthFailure(totpSessionExpiredMessage, 'mfa_session_expired');
    }
    try {
      final assertion =
          await TotpMultiFactorGenerator.getAssertionForEnrollment(
            secret,
            code.trim(),
          );
      await _user.multiFactor.enroll(assertion, displayName: 'TOTP');
    } on FirebaseAuthException catch (error) {
      throw totpFailure(error);
    }
  }
}
