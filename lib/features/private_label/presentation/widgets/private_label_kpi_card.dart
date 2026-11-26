import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Monthly KPI card.
///
/// [compact] = home dashboard summary; otherwise the full card on the page.
class PrivateLabelKpiCard extends StatelessWidget {
  final PrivateLabelKpi? kpi;
  final bool compact;
  final bool isLoading;
  final bool isSyncing;
  final int pendingCount;
  final VoidCallback? onOpen;
  final VoidCallback? onOpenCatalog;
  final String? catalogButtonLabel;
  final VoidCallback? onRegisterRestToday;
  final VoidCallback? onCancelRestToday;

  const PrivateLabelKpiCard({
    super.key,
    required this.kpi,
    this.compact = false,
    this.isLoading = false,
    this.isSyncing = false,
    this.pendingCount = 0,
    this.onOpen,
    this.onOpenCatalog,
    this.catalogButtonLabel,
    this.onRegisterRestToday,
    this.onCancelRestToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final k = kpi;
    final percent = k?.scorePercentage ?? 0;

    final card = Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.sell_rounded, size: 20, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'العلامة الخاصة',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'مؤشر الأداء الشهري (KPI)',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (isSyncing)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  ),
                ),
              _AnimatedPercent(value: percent, isLoading: isLoading && k == null),
            ],
          ),
          const SizedBox(height: 14),
          _AnimatedProgressBar(progress: k?.progress ?? 0),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                k == null
                    ? 'بنحمّل بيانات الشهر...'
                    : '${k.completedDays} من ${k.daysInMonth} يوم',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (k != null)
                Text(
                  'إجازات: ${k.restDaysUsed}/${k.restAllowance}',
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          if (k != null) ...[
            const SizedBox(height: 12),
            _TodayBanner(kpi: k, pendingCount: pendingCount),
          ],
          if (!compact && k != null) ...[
            const SizedBox(height: 14),
            _StatsRow(kpi: k),
            if (k.todayStatus == PrivateLabelTodayStatus.pending && onRegisterRestToday != null) ...[
              const SizedBox(height: 12),
              _RestButton(
                label: k.remainingRestDays > 0
                    ? 'تسجيل النهارده إجازة · المتبقي ${k.remainingRestDays}'
                    : 'خلّصت رصيد الإجازات للشهر ده',
                icon: Icons.beach_access_rounded,
                onPressed: k.remainingRestDays > 0 ? onRegisterRestToday : null,
              ),
            ],
            if (k.todayStatus == PrivateLabelTodayStatus.rest && onCancelRestToday != null) ...[
              const SizedBox(height: 12),
              _RestButton(
                label: 'إلغاء إجازة النهارده',
                icon: Icons.event_busy_rounded,
                onPressed: onCancelRestToday,
              ),
            ],
          ],
          if (!compact && onOpenCatalog != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                onPressed: onOpenCatalog,
                icon: const Icon(Icons.inventory_2_rounded, size: 18),
                label: Text(catalogButtonLabel ?? 'الكتالوج'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ],
          if (compact && (onOpen != null || onOpenCatalog != null)) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onOpenCatalog != null)
                  OutlinedButton.icon(
                    onPressed: onOpenCatalog,
                    icon: const Icon(Icons.inventory_2_rounded, size: 18),
                    label: Text(catalogButtonLabel ?? 'الكتالوج'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: const StadiumBorder(),
                    ),
                  ),
                if (onOpen != null)
                  FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      textDirection: TextDirection.ltr,
                    ),
                    label: const Text('فتح العلامة الخاصة'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: const StadiumBorder(),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    if (!compact || onOpen == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        hoverColor: cs.primary.withValues(alpha: 0.05),
        child: card,
      ),
    );
  }
}

class _AnimatedPercent extends StatelessWidget {
  final double value;
  final bool isLoading;

  const _AnimatedPercent({required this.value, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (isLoading) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.primary),
      );
    }
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: reduce ? Duration.zero : AppMotionDurations.long2,
      curve: AppMotionCurves.emphasizedDecelerate,
      builder: (context, v, _) => Text(
        '${v.round()}%',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  final double progress;

  const _AnimatedProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0, 1)),
      duration: reduce ? Duration.zero : AppMotionDurations.long2,
      curve: AppMotionCurves.emphasizedDecelerate,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 10,
          backgroundColor: cs.surfaceContainerHighest,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _TodayBanner extends StatelessWidget {
  final PrivateLabelKpi kpi;
  final int pendingCount;

  const _TodayBanner({required this.kpi, required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    late final IconData icon;
    late final String title;
    late final String subtitle;
    late final Color accent;

    switch (kpi.todayStatus) {
      case PrivateLabelTodayStatus.achieved:
        icon = Icons.task_alt_rounded;
        title = '${kpi.todayAuditsCount} منتج موثق النهارده';
        subtitle = '';
        accent = cs.primary;
      case PrivateLabelTodayStatus.rest:
        icon = Icons.beach_access_rounded;
        title = 'النهارده متسجل إجازة';
        subtitle = 'اليوم محسوب في المؤشر كأنه تاسك اتعمل';
        accent = cs.tertiary;
      case PrivateLabelTodayStatus.pending:
        icon = Icons.hourglass_top_rounded;
        title = 'في انتظار توثيق النهارده';
        subtitle = 'لسه مارفعتش صور النهارده';
        accent = cs.secondary;
      case PrivateLabelTodayStatus.outsideMonth:
        icon = Icons.calendar_month_rounded;
        title = 'شهر سابق';
        subtitle = 'بتعرض بيانات شهر مش الشهر الحالي';
        accent = cs.outline;
    }

    return PrivateLabelAccentContainer(
      accent: accent,
      child: Row(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (pendingCount > 0)
            PrivateLabelStatusPill(
              icon: Icons.cloud_upload_rounded,
              label: '$pendingCount محفوظ',
              color: cs.secondary,
            ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final PrivateLabelKpi kpi;

  const _StatsRow({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _Stat(
            icon: Icons.task_alt_rounded,
            value: '${kpi.achievedDays}',
            label: 'أيام محققة',
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stat(
            icon: Icons.beach_access_rounded,
            value: '${kpi.remainingRestDays}',
            label: 'إجازات متبقية',
            color: cs.tertiary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stat(
            icon: Icons.event_busy_rounded,
            value: '${kpi.missedDays}',
            label: 'أيام فايتة',
            color: cs.error,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RestButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _RestButton({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
