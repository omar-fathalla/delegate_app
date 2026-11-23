import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Completes a pending second-factor sign-in with a 6-digit TOTP code.
///
/// Throws an [AuthFailure] with a readable Arabic message when the code is
/// wrong or the sign-in window expired. Completes normally once the Firebase
/// session exists.
typedef MfaCodeResolver = Future<void> Function(String code);

/// Staff password was right, but the account has TOTP two-step verification
/// (TAS-207). Login is not finished until [resolve] succeeds with the code
/// from the user's authenticator app.
///
/// [pendingDelegates] are the staff profiles that the password matched. The
/// login continues with them exactly as after a normal password sign-in.
class MfaRequiredFailure extends AuthFailure {
  const MfaRequiredFailure({
    required this.resolve,
    this.pendingDelegates = const [],
  }) : super(defaultMessage, failureCode);

  static const String failureCode = 'mfa_required';
  static const String defaultMessage =
      'أدخل رمز التحقق من تطبيق المصادقة لإكمال تسجيل الدخول.';

  final MfaCodeResolver resolve;
  final List<Delegate> pendingDelegates;

  MfaRequiredFailure withPendingDelegates(List<Delegate> delegates) =>
      MfaRequiredFailure(resolve: resolve, pendingDelegates: delegates);

  @override
  List<Object> get props => [...super.props, resolve, pendingDelegates];
}
