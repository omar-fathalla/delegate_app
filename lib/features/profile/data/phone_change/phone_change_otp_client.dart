// TAS-112: sends the OTP to the NEW number and puts it on the delegate's
// Auth user. A user that already has a phone (login OTP) gets it replaced
// with updatePhoneNumber; otherwise the phone is linked. It never signs in
// with the phone credential, so the delegate custom-token uid stays.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

class PhoneChangeOtpClient {
  PhoneChangeOtpClient(this.auth);

  final FirebaseAuth auth;
  String? _verificationId;
  int? _resendToken;

  /// Completes when the code was sent (or the number was verified
  /// instantly, then [onAutoVerified] runs after the phone is on the user).
  Future<void> sendCode({
    required String e164Phone,
    bool resend = false,
    required void Function() onAutoVerified,
    required void Function(String code) onFailed,
  }) {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      forceResendingToken: resend ? _resendToken : null,
      verificationCompleted: (credential) async {
        try {
          await _apply(credential);
          onAutoVerified();
        } on FirebaseAuthException catch (e) {
          onFailed(e.code);
        } catch (_) {
          onFailed('unknown');
        }
        finish();
      },
      verificationFailed: (e) {
        onFailed(e.code);
        finish();
      },
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        finish();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId ??= verificationId;
        finish();
      },
    );
    return done.future;
  }

  /// Throws [FirebaseAuthException] (e.g. invalid-verification-code).
  Future<void> confirmCode(String smsCode) async {
    final id = _verificationId;
    if (id == null) {
      throw FirebaseAuthException(code: 'missing-verification-id');
    }
    await _apply(PhoneAuthProvider.credential(verificationId: id, smsCode: smsCode.trim()));
  }

  Future<void> _apply(PhoneAuthCredential credential) async {
    final user = auth.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'user-not-found');
    final hasPhone = user.providerData.any((p) => p.providerId == PhoneAuthProvider.PROVIDER_ID);
    if (hasPhone) {
      await user.updatePhoneNumber(credential);
    } else {
      await user.linkWithCredential(credential);
    }
  }
}
