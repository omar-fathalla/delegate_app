import 'dart:async';

import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseDelegatePhoneOtpClient implements DelegatePhoneOtpClient {
  final FirebaseAuth auth;
  final ConfirmDelegateOtpApi? confirmOtpApi;

  FirebaseDelegatePhoneOtpClient(this.auth, {this.confirmOtpApi});

  bool _linked = false;
  Future<void>? _linking;

  @override
  Future<void> sendCode({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(OtpCodeDispatch sent) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(PhoneOtpLinkException error) onFailed,
    void Function()? onAutoRetrievalTimeout,
  }) {
    final completer = Completer<void>();
    var manualEntryReady = false;
    var autoVerified = false;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    void showManualEntry(String verificationId, int? resendToken) {
      if (autoVerified || manualEntryReady) return;
      manualEntryReady = true;
      onCodeSent(
        OtpCodeDispatch(
          verificationId: verificationId,
          resendToken: resendToken,
        ),
      );
      finish();
    }

    // verificationCompleted is instant verification on both platforms.
    // The PhoneAuthCredential is linked with the same `_link` method a typed
    // code uses (`linkWithCredential`, or `reauthenticateWithCredential` when
    // this user already has a phone provider). It never calls
    // `signInWithCredential`, so the delegate custom-token uid stays put.
    //
    // Android: Play Services instant verification, or SMS Retriever when the
    // SMS contains this build's app hash. See SmartAuthSmsRetriever.
    //
    // iOS: a silent APNs push. TODO(ios-apns): this callback does not run
    // until APNs is configured for the iOS app — upload the APNs auth key in
    // Firebase Console → Project settings → Cloud Messaging, enable Push
    // Notifications on the Apple target, and register the iOS app. Until
    // then iOS falls through to `codeSent` and the QuickType one-time-code
    // bar. Do not block the build on that setup.
    //
    // `codeAutoRetrievalTimeout` is not a failure. Android stops waiting for
    // the SMS, and iOS stops waiting for the silent push. The typed / QuickType
    // field stays available.
    auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      timeout: DelegateOtpConfig.resendCooldown,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) async {
        try {
          await _link(credential);
          autoVerified = true;
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
        showManualEntry(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        onAutoRetrievalTimeout?.call();
        showManualEntry(verificationId, forceResendingToken);
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

  /// One link at a time. A second caller (autofill racing instant
  /// verification) waits and does not send the credential again after the
  /// first link is accepted.
  Future<void> _link(PhoneAuthCredential credential) async {
    if (_linked) return;
    final pending = _linking;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
      if (_linked) return;
    }

    final run = _linkOnce(credential);
    _linking = run;
    try {
      await run;
      _linked = true;
    } finally {
      if (identical(_linking, run)) _linking = null;
    }
  }

  Future<void> _linkOnce(PhoneAuthCredential credential) async {
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
        } on FirebaseAuthException catch (again) {
          throw phoneOtpExceptionForCode(again.code);
        }
      } else {
        throw phoneOtpExceptionForCode(error.code);
      }
    }

    await _confirmServerPossession();
  }

  /// Asks Cloud Functions to set otp_verified after a real phone link, then
  /// refreshes the ID token so Firestore rules see the claim. When the server
  /// is not enforcing OTP (no otp_required claim) a missing callable is
  /// ignored so local OTP UI still works before deploy.
  Future<void> _confirmServerPossession() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const PhoneOtpLinkException(
        PhoneOtpLinkFailure.notSignedIn,
        phoneOtpNotSignedInMessage,
      );
    }

    final api = confirmOtpApi;
    if (api == null) {
      await user.getIdToken(true);
      return;
    }

    IdTokenResult token;
    try {
      token = await user.getIdTokenResult();
    } catch (_) {
      token = await user.getIdTokenResult(true);
    }
    final otpRequired = token.claims?['otp_required'] == true;

    try {
      await api.confirm();
      await user.getIdToken(true);
    } on ConfirmDelegateOtpException catch (error) {
      if (!otpRequired && error.reason == 'unavailable') {
        return;
      }
      throw PhoneOtpLinkException(
        PhoneOtpLinkFailure.other,
        _messageForConfirmReason(error.reason),
      );
    } catch (_) {
      if (!otpRequired) return;
      throw const PhoneOtpLinkException(
        PhoneOtpLinkFailure.other,
        phoneOtpGenericMessage,
      );
    }
  }
}

String _messageForConfirmReason(String reason) {
  switch (reason) {
    case 'phone_mismatch':
      return phoneOtpAlreadyInUseMessage;
    case 'not_signed_in':
      return phoneOtpNotSignedInMessage;
    case 'phone_not_linked':
      return phoneOtpGenericMessage;
    default:
      return phoneOtpGenericMessage;
  }
}
