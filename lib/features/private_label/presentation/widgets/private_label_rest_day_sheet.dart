import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:flutter/material.dart';

/// Confirmation sheet for registering / cancelling a rest day.
///
/// Returns `true` when the marketer confirms.
Future<bool> confirmPrivateLabelRestDay({
  required BuildContext context,
  required String date,
  required int remainingRestDays,
  required int restAllowance,
  bool cancel = false,
}) async {
  final result = await showPrivateLabelSheet<bool>(
    context: context,
    heightFactor: null,
    builder: (ctx, layout) => _RestDaySheet(
      layout: layout,
      date: date,
      remaining: remainingRestDays,
      allowance: restAllowance,
      cancel: cancel,
    ),
  );
  return result ?? false;
}

class _RestDaySheet extends StatelessWidget {
  final PrivateLabelSheetLayout layout;
  final String date;
  final int remaining;
  final int allowance;
  final bool cancel;

  const _RestDaySheet({
    required this.layout,
    required this.date,
    required this.remaining,
    required this.allowance,
    required this.cancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dayTitle = PrivateLabelLabels.dayTitle(date);
    final afterRemaining = cancel ? remaining + 1 : remaining - 1;

    return PrivateLabelSheetFrame(
      layout: layout,
      icon: cancel ? Icons.event_busy_rounded : Icons.beach_access_rounded,
      title: cancel ? 'إلغاء الإجازة' : 'تسجيل اليوم كإجازة',
      subtitle: dayTitle,
      actions: PrivateLabelConnectedActions(
        secondaryLabel: 'رجوع',
        primaryLabel: cancel ? 'إلغاء الإجازة' : 'تأكيد الإجازة',
        primaryIcon: cancel ? Icons.event_busy_rounded : Icons.check_rounded,
        primaryColor: cancel ? cs.error : null,
        onPrimaryColor: cancel ? cs.onError : null,
        onPrimary: () => Navigator.of(context).pop(true),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            cancel
                ? 'هل تريد إلغاء إجازة يوم $dayTitle؟ سيرجع اليوم لرصيدك ويُحسب كيوم عمل محتاج توثيق.'
                : 'هل تود تسجيل يوم $dayTitle كإجازة أسبوعية؟ اليوم هيتحسب مكتمل 100% في نسبة الشهر.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface, height: 1.5),
          ),
          const SizedBox(height: 16),
          PrivateLabelAccentContainer(
            accent: cs.primary,
            child: Row(
              children: [
                Icon(Icons.event_available_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'رصيد الإجازات بعد العملية',
                        style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${afterRemaining.clamp(0, allowance)} من $allowance أيام',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!cancel) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'لو نزلت الشغل ورفعت صور في نفس اليوم، هيتحول تلقائياً ليوم عمل مكتمل والإجازة ترجع لرصيدك.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
