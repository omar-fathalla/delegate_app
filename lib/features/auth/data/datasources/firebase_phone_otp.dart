import 'dart:async';

import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseDelegatePhoneOtpClient implements DelegatePhoneOtpClient {
  final FirebaseAuth auth;

  FirebaseDelegatePhoneOtpClient(this.auth);

  @override
  Future<void> sendCode({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(OtpCodeDispatch sent) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(PhoneOtpLinkException error) onFailed,
  }) {
    final completer = Completer<void>();
    var manualEntryReady = false;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      timeout: DelegateOtpConfig.resendCooldown,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) async {
        try {
          await _link(credential);
          onAutoVerified();
        } on PhoneOtpLinkException catch (error) {
          onFailed(error);
        } catch (_) {
          onFailed(
            const PhoneOtpLinkException(
              PhoneOtpLinkFailure.other,
              phoneOtpGenericMessage,
            ),
          );
        }
        finish();
      },
      verificationFailed: (exception) {
        onFailed(phoneOtpExceptionForCode(exception.code));
        finish();
      },
      codeSent: (verificationId, resendToken) {
        if (manualEntryReady) return;
        manualEntryReady = true;
        onCodeSent(
          OtpCodeDispatch(
            verificationId: verificationId,
            resendToken: resendToken,
          ),
        );
        finish();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (manualEntryReady) return;
        manualEntryReady = true;
        onCodeSent(
          OtpCodeDispatch(
            verificationId: verificationId,
            resendToken: forceResendingToken,
          ),
        );
        finish();
      },
    );

    return completer.future;
  }

  @override
  Future<void> confirmCode({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return _link(credential);
  }

  Future<void> _link(PhoneAuthCredential credential) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const PhoneOtpLinkException(
        PhoneOtpLinkFailure.notSignedIn,
        phoneOtpNotSignedInMessage,
      );
    }

    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (actionForLinkError(error.code) == PhoneOtpLinkAction.reauthenticate) {
        try {
          await user.reauthenticateWithCredential(credential);
          return;
        } on FirebaseAuthException catch (again) {
          throw phoneOtpExceptionForCode(again.code);
        }
      }
      throw phoneOtpExceptionForCode(error.code);
    }
  }
}
