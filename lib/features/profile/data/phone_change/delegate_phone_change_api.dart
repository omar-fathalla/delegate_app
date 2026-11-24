// TAS-112: a delegate changes its own phone number with an OTP on the new
// number. requestDelegatePhoneChange checks the national ID and that the
// number is free; confirmDelegatePhoneChange applies it after the app linked
// the verified number to the delegate's Auth user.
import 'package:cloud_functions/cloud_functions.dart';

/// Server reasons the UI shows a message for.
enum PhoneChangeFailure {
  badPhone,
  nationalIdMismatch,
  samePhone,
  phoneTaken,
  tooMany,
  expired,
  notVerified,
  other,
}

PhoneChangeFailure phoneChangeFailureFor(String? reason) {
  switch (reason) {
    case 'bad_phone':
      return PhoneChangeFailure.badPhone;
    case 'national_id_mismatch':
    case 'bad_national_id':
      return PhoneChangeFailure.nationalIdMismatch;
    case 'same_phone':
      return PhoneChangeFailure.samePhone;
    case 'phone_taken':
      return PhoneChangeFailure.phoneTaken;
    case 'too_many':
      return PhoneChangeFailure.tooMany;
    case 'expired':
    case 'no_request':
      return PhoneChangeFailure.expired;
    case 'phone_not_verified':
      return PhoneChangeFailure.notVerified;
    default:
      return PhoneChangeFailure.other;
  }
}

class PhoneChangeException implements Exception {
  const PhoneChangeException(this.failure);
  final PhoneChangeFailure failure;
  @override
  String toString() => 'PhoneChangeException($failure)';
}

typedef PhoneChangeCall = Future<Object?> Function(
  String name,
  Map<String, dynamic> data,
);

class DelegatePhoneChangeApi {
  DelegatePhoneChangeApi({PhoneChangeCall? call}) : _call = call ?? _defaultCall;

  final PhoneChangeCall _call;

  static Future<Object?> _defaultCall(String name, Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(name)
        .call<Object?>(data);
    return result.data;
  }

  Future<Object?> _run(String name, Map<String, dynamic> data) async {
    try {
      return await _call(name, data);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map ? details['reason'] as String? : null;
      throw PhoneChangeException(phoneChangeFailureFor(reason));
    } on PhoneChangeException {
      rethrow;
    } catch (_) {
      throw const PhoneChangeException(PhoneChangeFailure.other);
    }
  }

  /// Returns the new number in E.164 (+201xxxxxxxxx) to send the code to.
  Future<String> request({required String newPhone, required String nationalId}) async {
    final data = await _run('requestDelegatePhoneChange', {
      'newPhone': newPhone.trim(),
      'nationalId': nationalId.trim(),
    });
    final e164 = data is Map ? data['e164'] : null;
    if (e164 is! String || e164.isEmpty) {
      throw const PhoneChangeException(PhoneChangeFailure.other);
    }
    return e164;
  }

  /// Applies the change; returns the stored number (01xxxxxxxxx).
  Future<String> confirm() async {
    final data = await _run('confirmDelegatePhoneChange', const {});
    final phone = data is Map ? data['phoneNumber'] : null;
    if (phone is! String || phone.isEmpty) {
      throw const PhoneChangeException(PhoneChangeFailure.other);
    }
    return phone;
  }
}
