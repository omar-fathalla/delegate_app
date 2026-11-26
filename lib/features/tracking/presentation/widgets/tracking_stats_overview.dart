import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:material_ui/material_ui.dart';

class TrackingStatsOverview extends StatelessWidget {
  final int totalCount;
  final int activeTrackingCount;
  final int insideCount;
  final int outsideCount;
  final int offlineCount;
  final String? selectedFilter;
  final ValueChanged<String>? onFilterChanged;

  /// HR web (TAS-148): every card shares one surface style and only the
  /// status cards (inside / outside) color their icon. False keeps the
  /// original colored cards.
  final bool uniformStyle;

  const TrackingStatsOverview({
    super.key,
    required this.totalCount,
    required this.activeTrackingCount,
    required this.insideCount,
    required this.outsideCount,
    required this.offlineCount,
    this.selectedFilter,
    this.onFilterChanged,
    this.uniformStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (uniformStyle) return _buildUniform(context);

    final cards = [
      _StatCardData(
        filterKey: 'all',
        title: 'الإجمالي',
        value: '$totalCount',
        icon: Icons.groups_rounded,
        color: colorScheme.primary,
        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderColor: colorScheme.primary.withValues(alpha: 0.25),
      ),
      _StatCardData(
        filterKey: 'tracking_active',
        title: 'التتبع',
        value: '$activeTrackingCount',
        icon: Icons.radar_rounded,
        color: colorScheme.primary,
        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderColor: colorScheme.primary.withValues(alpha: 0.25),
      ),
      _StatCardData(
        filterKey: 'inside',
        title: 'داخل',
        value: '$insideCount',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF2E7D32),
        backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.08),
        borderColor: const Color(0xFF2E7D32).withValues(alpha: 0.25),
      ),
      _StatCardData(
        filterKey: 'outside',
        title: 'خارج النطاق',
        value: '$outsideCount',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFC65102),
        backgroundColor: colorScheme.surfaceContainerLow,
        borderColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      _StatCardData(
        filterKey: 'offline',
        title: 'غير متصل',
        value: '$offlineCount',
        icon: Icons.cloud_off_rounded,
        color: const Color(0xFF757575),
        backgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: _buildCard(cards[i], colorScheme),
          ),
        ],
      ],
    );
  }

  Widget _buildCard(_StatCardData data, ColorScheme colorScheme) {
    final isSelected =
        selectedFilter != null && selectedFilter == data.filterKey;

    return MouseRegion(
      cursor: onFilterChanged != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onFilterChanged != null
            ? () {
                if (selectedFilter == data.filterKey) {
                  onFilterChanged!('all');
                } else {
                  onFilterChanged!(data.filterKey);
                }
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? data.color.withValues(alpha: 0.16)
                : data.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? data.color : data.borderColor,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: data.color.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(data.icon, size: 13, color: data.color),
                  const SizedBox(width: 3),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      data.value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: data.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                data.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected ? data.color : colorScheme.onSurfaceVariant,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on TrackingStatsOverview {
  Widget _buildUniform(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = HrStatusColors.of(context);
    final neutral = colorScheme.onSurfaceVariant;
    final cards = <(String, String, int, IconData, Color)>[
      ('all', 'الإجمالي', totalCount, Icons.groups_outlined, neutral),
      (
        'tracking_active',
        'التتبع مفعّل',
        activeTrackingCount,
        Icons.radar_rounded,
        neutral,
      ),
      (
        'inside',
        'داخل النطاق',
        insideCount,
        Icons.check_circle_outline_rounded,
        status.success,
      ),
      (
        'outside',
        'خارج النطاق',
        outsideCount,
        Icons.warning_amber_rounded,
        status.warning,
      ),
      ('offline', 'غير متصل', offlineCount, Icons.cloud_off_rounded, neutral),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow windows stack icon, number and label in each card.
        final compact = constraints.maxWidth < 720;
        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: _uniformCard(
                  context,
                  filterKey: cards[i].$1,
                  title: cards[i].$2,
                  value: cards[i].$3,
                  icon: cards[i].$4,
                  iconColor: cards[i].$5,
                  compact: compact,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _uniformCard(
    BuildContext context, {
    required String filterKey,
    required String title,
    required int value,
    required IconData icon,
    required Color iconColor,
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = selectedFilter == filterKey;
    final radius = BorderRadius.circular(HrRadius.card);
    final valueText = Text(
      '$value',
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontSize: compact ? HrFont.titleMedium : HrFont.titleLarge,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    );
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: compact ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: HrFont.labelMedium,
        color: colorScheme.onSurfaceVariant,
      ),
    );
    final onTap = onFilterChanged == null
        ? null
        : () => onFilterChanged!(selected ? 'all' : filterKey);

    return Material(
      key: ValueKey('tracking_kpi_$filterKey'),
      color: selected
          ? colorScheme.secondaryContainer
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: iconColor),
                    const SizedBox(height: 4),
                    valueText,
                    titleText,
                  ],
                )
              : Row(
                  children: [
                    Icon(icon, size: 24, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [valueText, titleText],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatCardData {
  final String filterKey;
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _StatCardData({
    required this.filterKey,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });
}
