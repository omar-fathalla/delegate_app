import 'package:flutter/material.dart';

class TrackingStatsOverview extends StatelessWidget {
  final int totalCount;
  final int activeTrackingCount;
  final int insideCount;
  final int outsideCount;
  final int offlineCount;
  final String? selectedFilter;
  final ValueChanged<String>? onFilterChanged;

  const TrackingStatsOverview({
    super.key,
    required this.totalCount,
    required this.activeTrackingCount,
    required this.insideCount,
    required this.outsideCount,
    required this.offlineCount,
    this.selectedFilter,
    this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
