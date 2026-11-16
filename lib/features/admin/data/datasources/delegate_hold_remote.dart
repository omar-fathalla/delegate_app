import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_hold_access.dart';

/// Arabic copy for a `setDelegateHold` failure reason.
String delegateHoldFailureMessage(String reason) {
  switch (reason) {
    case 'caller_not_allowed':
    case 'caller_not_staff':
    case 'permission-denied':
      return 'ليس لديك صلاحية إيقاف أو إعادة تفعيل هذا المندوب.';
    case 'out_of_scope':
      return 'هذا المندوب خارج نطاق صلاحيتك.';
    case 'caller_inactive':
      return 'حسابك غير نشط.';
    case 'status_not_actionable':
      return 'لا يمكن تغيير حالة هذا المندوب حالياً.';
    case 'hold_not_present':
      return 'هذا الإيقاف غير موجود على حساب المندوب.';
    case 'hold_not_allowed':
      return delegateHoldNotAllowedMessage;
    default:
      return 'تعذر إتمام العملية. حاول مرة أخرى.';
  }
}

class DelegateHoldException implements Exception {
  DelegateHoldException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client for the named callable `setDelegateHold` (us-central1).
class DelegateHoldRemote {
  DelegateHoldRemote({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> setDelegateHold({
    required String uid,
    required String organizationUID,
    required String companyUID,
    required String op,
    String hold = 'admin_suspend',
    String? note,
  }) async {
    try {
      final result = await _functions.httpsCallable('setDelegateHold').call({
        'uid': uid,
        'orgId': organizationUID,
        'companyId': companyUID,
        'hold': hold,
        'op': op,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
      final raw = result.data;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return const {};
    } on FirebaseFunctionsException catch (e) {
      throw DelegateHoldException(_messageFor(e));
    } catch (_) {
      throw DelegateHoldException('تعذر إتمام العملية. حاول مرة أخرى.');
    }
  }

  String _messageFor(FirebaseFunctionsException e) {
    final reason = () {
      final details = e.details;
      if (details is Map && details['reason'] != null) {
        return details['reason'].toString();
      }
      return e.message ?? e.code;
    }();
    return delegateHoldFailureMessage(reason);
  }
}
