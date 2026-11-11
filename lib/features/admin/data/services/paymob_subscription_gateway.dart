import 'package:cloud_functions/cloud_functions.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';

/// Calls [createSubscriptionCheckout] on the server. The function quotes the
/// request and creates a Paymob test-mode intention; this class never sends
/// an amount and never holds Paymob keys.
class PaymobSubscriptionGateway implements SubscriptionPaymentGateway {
  final FirebaseFunctions _functions;

  PaymobSubscriptionGateway({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  Future<Either<Failure, PaymentCheckout>> startCheckout({
    required String requestId,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('createSubscriptionCheckout')
          .call({'requestId': requestId});
      final data = Map<String, dynamic>.from(result.data as Map);
      final raw = (data['checkoutUrl'] ?? '').toString();
      final url = Uri.tryParse(raw);
      if (url == null || !url.hasScheme) {
        return const Left(ServerFailure('تعذر فتح صفحة الدفع. أعد المحاولة.'));
      }
      return Right(PaymentCheckout(url));
    } on FirebaseFunctionsException catch (e) {
      return Left(ServerFailure(_message(e)));
    } catch (_) {
      return const Left(ServerFailure('تعذر بدء الدفع. أعد المحاولة.'));
    }
  }

  String _message(FirebaseFunctionsException e) {
    if (e.message != null && e.message!.trim().isNotEmpty) {
      return e.message!.trim();
    }
    final reason =
        (e.details is Map ? (e.details as Map)['reason'] : null)?.toString() ??
        e.code;
    switch (reason) {
      case 'paymob_not_configured':
        return 'تم حفظ الطلب بانتظار الدفع، لكن دفع Paymob غير مضبوط على الخادم بعد.';
      case 'paymob_live_forbidden':
      case 'paymob_test_keys_required':
        return 'دفع Paymob على بيئة الاختبار فقط. مفاتيح الإنتاج مرفوضة.';
      case 'sign_in_required':
      case 'unauthenticated':
        return 'يجب تسجيل الدخول أولاً.';
      case 'already_paid':
        return 'هذا الطلب مدفوع مسبقاً.';
      case 'already_covered':
        return 'أحد المناديب المحددين مغطى بالفعل في طلب آخر لنفس الفترة.';
      default:
        return 'تعذر بدء الدفع. أعد المحاولة.';
    }
  }
}
