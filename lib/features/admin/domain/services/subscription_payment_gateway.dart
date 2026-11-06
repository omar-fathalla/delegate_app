import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';

/// Where the app sends the supervisor to pay.
class PaymentCheckout {
  final Uri checkoutUrl;
  const PaymentCheckout(this.checkoutUrl);
}

/// Hook for Engineering's Paymob module.
///
/// Contract:
/// - [startCheckout] asks the SERVER to create the Paymob order for the
///   `delegate_requests/{requestId}` doc. The server computes the amount with
///   `quoteSubscriptionRequest` (functions/src/subscription_jobs.ts); the app
///   never sends an amount and never holds Paymob keys.
/// - The request becomes paid only when Paymob's webhook is HMAC-verified on
///   the server and `applyVerifiedSubscriptionPayment` runs. The app just
///   watches `paymentStatus` on the request doc.
abstract class SubscriptionPaymentGateway {
  Future<Either<Failure, PaymentCheckout>> startCheckout({required String requestId});
}

/// Default until the Paymob module lands: the request is saved as
/// "awaiting payment" and the supervisor is told online payment isn't live yet.
class PaymobNotConnectedGateway implements SubscriptionPaymentGateway {
  const PaymobNotConnectedGateway();

  static const String message =
      'تم حفظ طلب التجديد بانتظار الدفع، لكن الدفع الإلكتروني عبر Paymob لم يُفعَّل بعد. سيتم تفعيله قريباً.';

  @override
  Future<Either<Failure, PaymentCheckout>> startCheckout({required String requestId}) async =>
      const Left(ServerFailure(message));
}
