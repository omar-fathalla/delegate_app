// TAS-49: a staff member's phone and email in users/{uid} are set by the
// updateOwnStaffContact callable, not by the client (the rules refuse it).
import 'package:cloud_functions/cloud_functions.dart';

class StaffContactApi {
  StaffContactApi({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  /// Sets users/{uid}.phoneNumber after the server checks the number is not
  /// used by another account. Returns the stored (normalized) number.
  Future<String> updatePhone(String phone) async {
    final res = await _functions
        .httpsCallable('updateOwnStaffContact')
        .call<Map<String, dynamic>>({'field': 'phone', 'value': phone});
    return (res.data['phoneNumber'] ?? phone).toString();
  }

  /// Copies the confirmed Firebase Auth email into users/{uid}.email.
  Future<void> syncEmail() async {
    await _functions.httpsCallable('updateOwnStaffContact').call<Map<String, dynamic>>({'field': 'email'});
  }
}

/// True when the confirmed Auth email differs from the users doc (the user
/// confirmed a new address through verifyBeforeUpdateEmail).
bool staffEmailNeedsSync(String? authEmail, Object? storedEmail) {
  final auth = (authEmail ?? '').trim().toLowerCase();
  if (auth.isEmpty) return false;
  final stored = (storedEmail ?? '').toString().trim().toLowerCase();
  return auth != stored;
}

/// Arabic message for an updateOwnStaffContact failure.
String staffContactErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final reason = details is Map ? details['reason']?.toString() : null;
    switch (reason) {
      case 'phone_taken':
        return 'الرقم ده مسجل على حساب تاني.';
      case 'bad_phone':
        return 'اكتب رقم موبايل مصري صحيح.';
      case 'not_staff':
      case 'delegate_token':
        return 'تغيير الرقم من هنا للموظفين بس.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'مفيش اتصال بالسيرفر، جرّب تاني.';
    }
  }
  return 'حصل خطأ أثناء التحديث، جرّب تاني.';
}
