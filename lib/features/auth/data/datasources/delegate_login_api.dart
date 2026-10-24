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
  });
}

class FirebaseDelegateLoginApi implements DelegateLoginApi {
  final FirebaseFunctions functions;

  FirebaseDelegateLoginApi(this.functions);

  @override
  Future<DelegateLoginResponse> login({
    required String phone,
    required String nationalId,
  }) async {
    try {
      final callable = functions.httpsCallable('delegateLoginV2');
      final result = await callable.call({
        'phone': phone,
        'nationalId': nationalId,
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
