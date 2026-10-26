import 'package:flutter/foundation.dart';
import 'package:pinput/pinput.dart';
import 'package:smart_auth/smart_auth.dart';

/// Android SMS Retriever listener used by [Pinput].
///
/// Pinput 5 replaced the old `androidSmsAutofillMethod` enum. Passing this
/// retriever is the `AndroidSmsAutofillMethod.smsRetrieverApi` path: Play
/// Services reads one SMS addressed to this app and Pinput fills every box.
/// It does not request `READ_SMS`. iOS ignores this listener; QuickType uses
/// [AutofillHints.oneTimeCode] on the same [Pinput].
///
/// TODO(android-sms-hash): SMS Retriever only delivers a message that ends
/// with this build's 11-character app hash. The hash is derived from the
/// package name and the cert that signed the running APK. Debug, local
/// release, and Play App Signing hashes are different. For Play-distributed
/// builds, add the Play app-signing SHA-256 in Firebase Console → Project
/// settings → Android app. Firebase's phone-auth SMS appends the matching
/// hash; do not hardcode one. `SmartAuth.getAppSignature()` prints the hash
/// of the cert that signed the build you are running. A missing hash does
/// not fail the build: the user can still type the code, and iOS QuickType
/// does not use this hash.
class SmartAuthSmsRetriever implements SmsRetriever {
  SmartAuthSmsRetriever(this._smartAuth);

  final SmartAuth _smartAuth;
  static bool _loggedSignature = false;

  /// One code per send. A resend mounts a new [Pinput], which listens again.
  @override
  bool get listenForMultipleSms => false;

  @override
  Future<String?> getSmsCode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    await _logAppSignature();
    final result = await _smartAuth.getSmsWithRetrieverApi(
      matcher: r'(?<!\d)\d{6}(?!\d)',
    );
    if (!result.hasData) return null;
    final code = result.data?.code?.trim();
    if (code == null || code.length != 6) return null;
    return code;
  }

  @override
  Future<void> dispose() {
    return _smartAuth.removeSmsRetrieverApiListener().then((_) {});
  }

  Future<void> _logAppSignature() async {
    if (!kDebugMode || _loggedSignature) return;
    _loggedSignature = true;
    final signature = await _smartAuth.getAppSignature();
    debugPrint(
      'Delegate OTP SMS Retriever hash for this build: ${signature.data ?? signature.error}. '
      'Play App Signing uses a different hash. See SmartAuthSmsRetriever.',
    );
  }
}
