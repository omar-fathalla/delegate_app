// TAS-20: a staff member who typed their phone gets the reset email from the
// requestStaffPasswordReset callable (Tashil template, link to
// tashil-account.web.app) instead of Firebase's default reset page.
import 'package:cloud_functions/cloud_functions.dart';

enum StaffResetOutcome {
  /// The server accepted the request (it answers the same whether or not the
  /// phone belongs to an account).
  sent,

  /// The phone is not a valid number; fall back to asking for the email.
  invalidPhone,

  /// Network or server failure.
  failed,
}

class StaffPasswordResetApi {
  StaffPasswordResetApi({Future<void> Function(String phone)? call})
      : _call = call ?? _defaultCall;

  final Future<void> Function(String phone) _call;

  static Future<void> _defaultCall(String phone) async {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('requestStaffPasswordReset')
        .call<Map<String, dynamic>>({'phone': phone});
  }

  Future<StaffResetOutcome> request(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return StaffResetOutcome.invalidPhone;
    try {
      await _call(trimmed);
      return StaffResetOutcome.sent;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'invalid-argument') return StaffResetOutcome.invalidPhone;
      return StaffResetOutcome.failed;
    } catch (_) {
      return StaffResetOutcome.failed;
    }
  }
}
