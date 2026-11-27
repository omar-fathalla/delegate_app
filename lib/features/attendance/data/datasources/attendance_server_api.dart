import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/core/error/failures.dart';

/// The callable is not deployed on this project yet (TAS-361 rollout):
/// the caller falls back to the old direct write.
class AttendanceServerUnavailable implements Exception {
  const AttendanceServerUnavailable();
}

/// The call may or may not have landed (timeout, network): the caller
/// checks the record on the server before telling the delegate anything.
class AttendanceServerUncertain implements Exception {
  const AttendanceServerUncertain();
}

/// Server side of attendance (TAS-361): `delegateCheckIn` / `delegateCheckOut`.
///
/// Refusals throw a [ServerFailure] with the server's Arabic message
/// (`details.message`), so the screen shows why (outside the branch, open
/// session, same branch today, ...).
abstract class AttendanceServerApi {
  Future<Map<String, dynamic>> checkIn(Map<String, dynamic> data);
  Future<Map<String, dynamic>> checkOut(Map<String, dynamic> data);
}

class FirebaseAttendanceServerApi implements AttendanceServerApi {
  FirebaseAttendanceServerApi(this.functions);

  final FirebaseFunctions functions;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<Map<String, dynamic>> checkIn(Map<String, dynamic> data) =>
      _call('delegateCheckIn', data);

  @override
  Future<Map<String, dynamic>> checkOut(Map<String, dynamic> data) =>
      _call('delegateCheckOut', data);

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final result = await functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: _timeout))
          .call<dynamic>(data)
          .timeout(_timeout + const Duration(seconds: 5));
      final raw = result.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : const {};
    } on FirebaseFunctionsException catch (e) {
      throw attendanceServerError(e.code, e.details, e.message);
    } on TimeoutException {
      throw const AttendanceServerUncertain();
    }
  }
}

/// Maps a callable error to what the data source does with it.
Object attendanceServerError(String code, Object? details, String? message) {
  switch (code) {
    case 'not-found':
    case 'unimplemented':
      return const AttendanceServerUnavailable();
    case 'deadline-exceeded':
    case 'unavailable':
    case 'internal':
    case 'unknown':
      return const AttendanceServerUncertain();
  }
  final fromDetails = details is Map ? details['message'] : null;
  final text = fromDetails is String && fromDetails.trim().isNotEmpty
      ? fromDetails
      : (message != null && message.trim().isNotEmpty
          ? message
          : 'تعذّر تسجيل العملية. حاول مرة تانية.');
  return ServerFailure(text);
}
