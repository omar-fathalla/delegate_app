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

  const DelegateLoginException(this.reason, [this.message]);

  @override
  String toString() => 'DelegateLoginException($reason)';
}

abstract class DelegateLoginApi {
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
    required String deviceId,
    String deviceModel = '',
  });
}

/// Profile returned by `staffPhoneLookup` before the password is checked.
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
    required this.uid,
    required this.email,
    required this.role,
    required this.displayName,
    required this.phoneNumber,
    this.organizationUID = '',
    this.organizationName = '',
    this.companyUID = '',
    this.companyName = '',
  });
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
      final uid = data['uid'];
      if (email is! String || !email.contains('@') || uid is! String || uid.isEmpty) {
        throw const StaffPhoneLookupException('unavailable');
      }
      String text(String key) {
        final value = data[key];
        return value is String ? value : '';
      }

      return StaffPhoneProfile(
        uid: uid,
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
  }) async {
    try {
      final callable = functions.httpsCallable('delegateLoginV2');
      final result = await callable.call({
        'phone': phone,
        'nationalId': nationalId,
        'deviceId': deviceId,
        if (deviceModel.isNotEmpty) 'deviceModel': deviceModel,
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
      throw DelegateLoginException(_reasonFor(error), error.message);
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
