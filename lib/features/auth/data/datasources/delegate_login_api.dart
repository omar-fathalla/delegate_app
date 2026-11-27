import 'package:cloud_functions/cloud_functions.dart';

class DelegateLoginResponse {
  final String token;
  final List<String> delegateIds;

  const DelegateLoginResponse({
    required this.token,
    required this.delegateIds,
  });
}

class DelegateLoginException implements Exception {
  final String reason;
  final String? message;

  /// TAS-367: extra server details (e.g. the supervisor to call on a device
  /// mismatch). Empty when the server sent none.
  final Map<String, dynamic> details;

  const DelegateLoginException(this.reason, [this.message, this.details = const {}]);

  @override
  String toString() => 'DelegateLoginException($reason)';
}

abstract class DelegateLoginApi {
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
    required String deviceId,
    String deviceModel = '',
    // TAS-261: the old Android Build.ID, so the server can move an old binding.
    String legacyDeviceId = '',
  });
}

/// Profile returned by `staffPhoneLookup`.
///
/// TAS-314: signed out, the callable returns the email only (everything else
/// is empty here). Signed in as the account owner, it returns the full
/// profile. [isComplete] tells the two apart.
class StaffPhoneProfile {
  final String uid;
  final String email;
  final String role;
  final String displayName;
  final String phoneNumber;
  final String organizationUID;
  final String organizationName;
  final String companyUID;
  final String companyName;

  const StaffPhoneProfile({
    required this.email,
    this.uid = '',
    this.role = '',
    this.displayName = '',
    this.phoneNumber = '',
    this.organizationUID = '',
    this.organizationName = '',
    this.companyUID = '',
    this.companyName = '',
  });

  /// False for the signed-out (email-only) answer.
  bool get isComplete => uid.isNotEmpty && role.isNotEmpty;
}

class StaffPhoneLookupException implements Exception {
  /// `not_found` means the phone is not a staff account.
  /// `unavailable` means the callable is not deployed yet, so the client may
  /// fall back to the users query until the tightened rules are published.
  final String reason;

  const StaffPhoneLookupException(this.reason);

  @override
  String toString() => 'StaffPhoneLookupException($reason)';
}

abstract class StaffPhoneLookupApi {
  /// Returns null when the phone is not a staff account.
  Future<StaffPhoneProfile?> lookup(String phone);
}

class FirebaseStaffPhoneLookupApi implements StaffPhoneLookupApi {
  final FirebaseFunctions functions;

  FirebaseStaffPhoneLookupApi(this.functions);

  @override
  Future<StaffPhoneProfile?> lookup(String phone) async {
    try {
      final callable = functions.httpsCallable('staffPhoneLookup');
      final result = await callable.call({'phone': phone});
      final raw = result.data;
      if (raw is! Map) {
        throw const StaffPhoneLookupException('unavailable');
      }
      final data = Map<String, dynamic>.from(raw);
      final email = data['email'];
      if (email is! String || !email.contains('@')) {
        throw const StaffPhoneLookupException('unavailable');
      }
      String text(String key) {
        final value = data[key];
        return value is String ? value : '';
      }

      // TAS-314: uid and role come back only to the signed-in owner.
      return StaffPhoneProfile(
        uid: text('uid'),
        email: email,
        role: text('role'),
        displayName: text('displayName'),
        phoneNumber: text('phoneNumber'),
        organizationUID: text('organizationUID'),
        organizationName: text('organizationName'),
        companyUID: text('companyUID'),
        companyName: text('companyName'),
      );
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final detailed = details is Map ? details['reason'] : null;
      if (detailed == 'not_found') return null;
      if (detailed == 'rate_limited') {
        throw const StaffPhoneLookupException('rate_limited');
      }
      if (detailed == 'invalid_phone' || detailed == 'missing_phone') {
        throw const StaffPhoneLookupException('invalid_phone');
      }
      if (error.code == 'not-found' ||
          error.code == 'unimplemented' ||
          error.code == 'unavailable' ||
          error.code == 'internal') {
        throw const StaffPhoneLookupException('unavailable');
      }
      throw const StaffPhoneLookupException('unavailable');
    }
  }
}

class FirebaseDelegateLoginApi implements DelegateLoginApi {
  final FirebaseFunctions functions;

  FirebaseDelegateLoginApi(this.functions);

  @override
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
    required String deviceId,
    String deviceModel = '',
    String legacyDeviceId = '',
  }) async {
    try {
      final callable = functions.httpsCallable('delegateLoginV2');
      final result = await callable.call({
        'phone': phone,
        'nationalId': nationalId,
        'deviceId': deviceId,
        if (deviceModel.isNotEmpty) 'deviceModel': deviceModel,
        if (legacyDeviceId.isNotEmpty) 'legacyDeviceId': legacyDeviceId,
      });
      final raw = result.data;
      if (raw is! Map) {
        throw const DelegateLoginException('unavailable');
      }
      final data = Map<String, dynamic>.from(raw);
      final token = data['token'];
      final ids = data['delegateIds'];
      if (token is! String || token.isEmpty || ids is! List) {
        throw const DelegateLoginException('unavailable');
      }
      return DelegateLoginResponse(
        token: token,
        delegateIds: ids.map((id) => id.toString()).where((id) => id.isNotEmpty).toList(),
      );
    } on FirebaseFunctionsException catch (error) {
      final raw = error.details;
      throw DelegateLoginException(
        _reasonFor(error),
        error.message,
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    }
  }

  String _reasonFor(FirebaseFunctionsException error) {
    final details = error.details;
    final detailed = details is Map ? details['reason'] : null;
    if (detailed is String && detailed.isNotEmpty) {
      if (detailed == 'device_mismatch') return 'device_mismatch';
      if (detailed == 'missing_device' || detailed == 'invalid_device') {
        return 'invalid_device';
      }
      if (detailed == 'not_found') return 'not_found';
      if (detailed == 'bad_credentials') return 'bad_credentials';
      if (detailed == 'account_inactive') return 'account_inactive';
      if (detailed == 'rate_limited') return 'rate_limited';
      if (detailed == 'missing_phone' || detailed == 'invalid_phone') {
        return 'invalid_phone';
      }
      if (detailed == 'missing_national_id' ||
          detailed == 'invalid_national_id' ||
          detailed == 'missing_fields') {
        return 'invalid_national_id';
      }
    }

    switch (error.code) {
      case 'unauthenticated':
        return 'bad_credentials';
      case 'not-found':
        return 'not_found';
      case 'permission-denied':
        return 'account_inactive';
      case 'resource-exhausted':
        return 'rate_limited';
      case 'invalid-argument':
        return 'invalid_national_id';
      default:
        return 'unavailable';
    }
  }
}

/// Confirms that the signed-in custom-token user linked a matching phone.
abstract class ConfirmDelegateOtpApi {
  Future<void> confirm();
}

class ConfirmDelegateOtpException implements Exception {
  final String reason;

  const ConfirmDelegateOtpException(this.reason);

  @override
  String toString() => 'ConfirmDelegateOtpException($reason)';
}

class FirebaseConfirmDelegateOtpApi implements ConfirmDelegateOtpApi {
  final FirebaseFunctions functions;

  FirebaseConfirmDelegateOtpApi(this.functions);

  @override
  Future<void> confirm() async {
    try {
      final callable = functions.httpsCallable('confirmDelegateOtp');
      final result = await callable.call(<String, dynamic>{});
      final raw = result.data;
      if (raw is! Map) {
        throw const ConfirmDelegateOtpException('unavailable');
      }
      final data = Map<String, dynamic>.from(raw);
      if (data['ok'] != true) {
        throw const ConfirmDelegateOtpException('unavailable');
      }
    } on FirebaseFunctionsException catch (error) {
      throw ConfirmDelegateOtpException(_reasonFor(error));
    }
  }

  String _reasonFor(FirebaseFunctionsException error) {
    final details = error.details;
    final detailed = details is Map ? details['reason'] : null;
    if (detailed is String && detailed.isNotEmpty) {
      switch (detailed) {
        case 'phone_not_linked':
        case 'phone_mismatch':
        case 'not_delegate':
        case 'not_signed_in':
          return detailed;
        default:
          break;
      }
    }
    switch (error.code) {
      case 'unauthenticated':
        return 'not_signed_in';
      case 'failed-precondition':
        return 'phone_not_linked';
      case 'permission-denied':
        return 'phone_mismatch';
      case 'not-found':
      case 'unimplemented':
      case 'unavailable':
      case 'internal':
        return 'unavailable';
      default:
        return 'unavailable';
    }
  }
}
