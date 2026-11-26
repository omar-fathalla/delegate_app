import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:material_ui/material_ui.dart';

/// One receipt for one renewal request (one Paymob payment, list of delegates).
class SubscriptionRenewalReceiptPage extends StatelessWidget {
  final RenewalReceipt receipt;

  const SubscriptionRenewalReceiptPage({super.key, required this.receipt});

  static const String title = 'إيصال التجديد';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final periodTitle = receipt.periodCode.isEmpty
        ? ''
        : SubscriptionCycleHelper.getCycleTitleArabic(
            SubscriptionCycleHelper.getCycleStartDateForCode(
              receipt.periodCode,
            ),
          );
    final status = switch (receipt.paymentStatus) {
      SubscriptionPaymentStatus.paid => 'مدفوع',
      SubscriptionPaymentStatus.pending => 'بانتظار الدفع',
      SubscriptionPaymentStatus.failed => 'فشل الدفع',
      SubscriptionPaymentStatus.expired => 'منتهٍ',
      _ => receipt.paymentStatus.name,
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              periodTitle.isEmpty ? receipt.periodCode : periodTitle,
              key: const Key('renewal_receipt_period'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('الحالة: $status', key: const Key('renewal_receipt_status')),
            Text(
              'عدد المناديب: ${receipt.delegateCount}',
              key: const Key('renewal_receipt_count'),
            ),
            Text(
              'الإجمالي: ${SubscriptionCycleHelper.formatEgp(receipt.amount)} ج.م',
              key: const Key('renewal_receipt_total'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: cs.primary,
              ),
            ),
            if (receipt.remainingMonths > 0)
              Text(
                'الأشهر المتبقية عند إصدار العرض: ${receipt.remainingMonths}',
              ),
            if (receipt.requestId.isNotEmpty)
              Text('رقم الطلب: ${receipt.requestId}'),
            if (receipt.transactionId != null)
              Text('رقم عملية Paymob: ${receipt.transactionId}'),
            if (receipt.companyName.isNotEmpty) Text(receipt.companyName),
            const Divider(height: 24),
            const Text(
              'المناديب',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final item in receipt.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.fullName.isEmpty ? item.uid : item.fullName),
                trailing: Text(
                  '${SubscriptionCycleHelper.formatEgp(item.fee)} ج.م',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
