/// Result of asking Firebase to send an SMS, before the user types a code.
class OtpCodeDispatch {
  final String verificationId;
  final int? resendToken;

  const OtpCodeDispatch({required this.verificationId, this.resendToken});
}

enum PhoneOtpLinkFailure {
  invalidCode,
  expired,
  credentialAlreadyInUse,
  notSignedIn,
  other,
}

class PhoneOtpLinkException implements Exception {
  final PhoneOtpLinkFailure failure;
  final String message;

  const PhoneOtpLinkException(this.failure, this.message);

  @override
  String toString() => message;
}

const phoneOtpInvalidCodeMessage = 'الرمز غير صحيح. حاول مرة أخرى.';
const phoneOtpExpiredMessage =
    'انتهت صلاحية الرمز. أعد الإرسال ثم أدخل الرمز الجديد.';
const phoneOtpAlreadyInUseMessage =
    'هذا الرقم مرتبط بحساب آخر. لا يمكن ربطه بهذا الحساب.';
const phoneOtpNotSignedInMessage = 'انتهت جلسة الدخول. سجّل الدخول من جديد.';
const phoneOtpGenericMessage = 'تعذر التحقق من الرقم. حاول مرة أخرى.';
const phoneOtpSendFailedMessage = 'تعذر إرسال رمز التحقق. حاول مرة أخرى.';

String messageForPhoneOtpFailure(PhoneOtpLinkFailure failure) {
  switch (failure) {
    case PhoneOtpLinkFailure.invalidCode:
      return phoneOtpInvalidCodeMessage;
    case PhoneOtpLinkFailure.expired:
      return phoneOtpExpiredMessage;
    case PhoneOtpLinkFailure.credentialAlreadyInUse:
      return phoneOtpAlreadyInUseMessage;
    case PhoneOtpLinkFailure.notSignedIn:
      return phoneOtpNotSignedInMessage;
    case PhoneOtpLinkFailure.other:
      return phoneOtpGenericMessage;
  }
}

/// `provider-already-linked` means this custom-token user already has a
/// phone provider, so the credential must be used to reauthenticate.
/// `credential-already-in-use` belongs to a different Auth user and must
/// not switch the session away from the delegate uid.
enum PhoneOtpLinkAction { linked, reauthenticate, fail }

PhoneOtpLinkAction actionForLinkError(String code) {
  if (code == 'provider-already-linked') {
    return PhoneOtpLinkAction.reauthenticate;
  }
  return PhoneOtpLinkAction.fail;
}

PhoneOtpLinkFailure failureForAuthCode(String code) {
  switch (code) {
    case 'invalid-verification-code':
    case 'invalid-verification-id':
      return PhoneOtpLinkFailure.invalidCode;
    case 'session-expired':
      return PhoneOtpLinkFailure.expired;
    case 'credential-already-in-use':
    case 'email-already-in-use':
      return PhoneOtpLinkFailure.credentialAlreadyInUse;
    default:
      return PhoneOtpLinkFailure.other;
  }
}

PhoneOtpLinkException phoneOtpExceptionForCode(String code) {
  final failure = failureForAuthCode(code);
  return PhoneOtpLinkException(failure, messageForPhoneOtpFailure(failure));
}

/// Sends a code to the delegate's own phone and links it to the current
/// Firebase user. Implementations must not call `signInWithCredential`.
abstract class DelegatePhoneOtpClient {
  Future<void> sendCode({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(OtpCodeDispatch sent) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(PhoneOtpLinkException error) onFailed,
    void Function()? onAutoRetrievalTimeout,
  });

  Future<void> confirmCode({
    required String verificationId,
    required String smsCode,
  });
}
