import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Payment-method and amount chips used on the subscription requests card.
class SubscriptionRequestPaymentChips extends StatelessWidget {
  const SubscriptionRequestPaymentChips({
    super.key,
    required this.request,
    this.onReceiptTap,
  });

  final DelegateSubscriptionRequest request;
  final void Function(String title, String url)? onReceiptTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        if (request.paymentMethod == SubscriptionPaymentMethod.freePromotion)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.history_rounded,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                  fill: 0,
                ),
                const SizedBox(width: 4),
                Text(
                  'مجاني (سجل 2026)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else if (request.paymentMethod == SubscriptionPaymentMethod.companyDeduction)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'خصم شركة',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          )
        else if (request.paymentMethod == SubscriptionPaymentMethod.instaPay) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF6B21A8).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF9333EA).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/instapay_logo.png',
                  width: 14,
                  height: 14,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 4),
                const Text(
                  'انستاباي',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9333EA),
                  ),
                ),
              ],
            ),
          ),
          if (request.receiptImageUrl != null)
            IconButton.filledTonal(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: 'عرض إشعار تحويل انستاباي',
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              onPressed: () => onReceiptTap?.call(
                'إشعار تحويل انستاباي - ${request.fullName}',
                request.receiptImageUrl!,
              ),
            ),
        ] else if (request.paymentMethod == SubscriptionPaymentMethod.paymob) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.credit_card_rounded,
                  size: 13,
                  color: colorScheme.onPrimaryContainer,
                  fill: 0,
                ),
                const SizedBox(width: 4),
                Text(
                  'دفع إلكتروني عبر Paymob',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${SubscriptionCycleHelper.formatEgp(request.fee)} ج.م (${request.remainingMonths} ${request.remainingMonths == 1 ? 'شهر' : 'أشهر'}) • ${request.paymentStatus.arabicLabel}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'إيصال إلكتروني',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'كود: ${request.receiptCode ?? "-"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (request.receiptImageUrl != null)
            IconButton.filledTonal(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: 'عرض الإيصال الإلكتروني',
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              onPressed: () => onReceiptTap?.call(
                'إيصال إلكتروني - كود ${request.receiptCode}',
                request.receiptImageUrl!,
              ),
            ),
        ],
        if (request.paymentMethod != SubscriptionPaymentMethod.paymob)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${SubscriptionCycleHelper.formatEgp(request.fee)} ج.م (${request.remainingMonths} ش) • ${request.paymentStatus.arabicLabel}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Status badge on a subscription request card, including Paymob payment states.
class SubscriptionRequestStatusBadge extends StatelessWidget {
  const SubscriptionRequestStatusBadge({
    super.key,
    required this.request,
    this.isDeleteRequest,
  });

  final DelegateSubscriptionRequest request;
  final bool? isDeleteRequest;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = request.status;
    final delete = isDeleteRequest ?? request.requestType == 'delete_delegate';
    final Color bg;
    final Color fg;
    final String label;
    final IconData icon;

    if (delete) {
      switch (status) {
        case SubscriptionRequestStatus.pending:
          bg = Colors.red.withValues(alpha: 0.12);
          fg = Colors.red.shade700;
          label = 'معلق للحذف';
          icon = Icons.delete_sweep_rounded;
        case SubscriptionRequestStatus.approved:
          bg = Colors.grey.withValues(alpha: 0.14);
          fg = Colors.grey.shade700;
          label = 'تم الحذف';
          icon = Icons.check_circle_rounded;
        case SubscriptionRequestStatus.rejected:
          bg = colorScheme.error.withValues(alpha: 0.12);
          fg = colorScheme.error;
          label = 'مرفوض';
          icon = Icons.cancel_rounded;
        case SubscriptionRequestStatus.cancelled:
          bg = Colors.grey.withValues(alpha: 0.14);
          fg = Colors.grey.shade700;
          label = 'ملغى';
          icon = Icons.block_rounded;
        case SubscriptionRequestStatus.expired:
          bg = Colors.orange.withValues(alpha: 0.14);
          fg = Colors.orange.shade800;
          label = 'منتهٍ';
          icon = Icons.timer_off_rounded;
      }
    } else if (request.isAwaitingPaymobPayment) {
      bg = colorScheme.tertiaryContainer;
      fg = colorScheme.onTertiaryContainer;
      label = 'بانتظار الدفع الإلكتروني';
      icon = Symbols.hourglass_top_rounded;
    } else if (request.paymentMethod == SubscriptionPaymentMethod.paymob &&
        request.paymentStatus == SubscriptionPaymentStatus.failed) {
      bg = colorScheme.errorContainer;
      fg = colorScheme.onErrorContainer;
      label = 'فشل الدفع';
      icon = Symbols.error_rounded;
    } else if (request.paymentMethod == SubscriptionPaymentMethod.paymob &&
        request.paymentStatus == SubscriptionPaymentStatus.paid &&
        status == SubscriptionRequestStatus.pending) {
      bg = colorScheme.primaryContainer;
      fg = colorScheme.onPrimaryContainer;
      label = 'مدفوع — بانتظار الاعتماد';
      icon = Symbols.verified_rounded;
    } else {
      switch (status) {
        case SubscriptionRequestStatus.pending:
          bg = colorScheme.primary.withValues(alpha: 0.12);
          fg = colorScheme.primary;
          label = 'قيد الانتظار';
          icon = Icons.hourglass_top_rounded;
        case SubscriptionRequestStatus.approved:
          bg = const Color(0xFF16A34A).withValues(alpha: 0.14);
          fg = const Color(0xFF16A34A);
          label = 'معتمد';
          icon = Icons.verified_rounded;
        case SubscriptionRequestStatus.rejected:
          bg = colorScheme.error.withValues(alpha: 0.12);
          fg = colorScheme.error;
          label = 'مرفوض';
          icon = Icons.cancel_rounded;
        case SubscriptionRequestStatus.cancelled:
          bg = Colors.grey.withValues(alpha: 0.14);
          fg = Colors.grey.shade700;
          label = 'ملغى';
          icon = Icons.block_rounded;
        case SubscriptionRequestStatus.expired:
          bg = Colors.orange.withValues(alpha: 0.14);
          fg = Colors.orange.shade800;
          label = 'منتهٍ';
          icon = Icons.timer_off_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fg.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg, fill: 0),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Approve/reject row, or the waiting message, for a pending request.
class SubscriptionRequestPendingActions extends StatelessWidget {
  const SubscriptionRequestPendingActions({
    super.key,
    required this.request,
    required this.role,
    this.isWide = false,
    this.onApprove,
    this.onReject,
  });

  final DelegateSubscriptionRequest request;
  final UserRole role;
  final bool isWide;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  bool get _isStaff =>
      role == UserRole.superAdmin || role == UserRole.technicalSupport;

  bool get _showApprove => _isStaff && !request.isAwaitingPaymobPayment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_showApprove) {
      return Row(
        mainAxisAlignment:
            isWide ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            fit: isWide ? FlexFit.loose : FlexFit.tight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: request.requestType == 'delete_delegate'
                    ? Colors.red.shade700
                    : const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                padding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onApprove,
              icon: Icon(
                request.requestType == 'delete_delegate'
                    ? Icons.delete_forever_rounded
                    : Icons.verified_rounded,
                size: 17,
              ),
              label: Text(
                request.requestType == 'delete_delegate'
                    ? 'اعتماد الحذف النهائي'
                    : request.isNationalIdUpdateRequest
                        ? 'اعتماد تعديل الرقم القومي'
                        : 'اعتماد وتفعيل',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            fit: isWide ? FlexFit.loose : FlexFit.tight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.7)),
                minimumSize: const Size(48, 48),
                padding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onReject,
              icon: const Icon(Icons.cancel_rounded, size: 17),
              label: Text(
                request.requestType == 'delete_delegate'
                    ? 'رفض طلب الحذف'
                    : request.isNationalIdUpdateRequest
                        ? 'رفض تعديل الرقم القومي'
                        : 'رفض الطلب',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: request.isAwaitingPaymobPayment
            ? colorScheme.tertiaryContainer
            : colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: request.isAwaitingPaymobPayment
              ? colorScheme.tertiary.withValues(alpha: 0.4)
              : colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            request.isAwaitingPaymobPayment
                ? Symbols.hourglass_top_rounded
                : Icons.hourglass_top_rounded,
            size: 16,
            color: request.isAwaitingPaymobPayment
                ? colorScheme.onTertiaryContainer
                : colorScheme.primary,
            fill: 0,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              request.isAwaitingPaymobPayment
                  ? 'بانتظار الدفع الإلكتروني. لا يمكن الاعتماد قبل تأكيد الدفع.'
                  : 'الطلب قيد الانتظار وبانتظار المراجعة والاعتماد.',
              style: TextStyle(
                fontSize: 11.5,
                color: request.isAwaitingPaymobPayment
                    ? colorScheme.onTertiaryContainer
                    : colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card used by tests and screenshots: the same chips, badge, and
/// pending actions the live requests page renders.
class SubscriptionRequestPaymentCard extends StatelessWidget {
  const SubscriptionRequestPaymentCard({
    super.key,
    required this.request,
    required this.role,
    this.onApprove,
    this.onReject,
  });

  final DelegateSubscriptionRequest request;
  final UserRole role;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SubscriptionRequestStatusBadge(request: request),
              ],
            ),
            const SizedBox(height: 10),
            SubscriptionRequestPaymentChips(request: request),
            if (request.status == SubscriptionRequestStatus.pending) ...[
              const SizedBox(height: 12),
              SubscriptionRequestPendingActions(
                request: request,
                role: role,
                onApprove: onApprove,
                onReject: onReject,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
