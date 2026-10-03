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
        title: 'إجمالي الحاضرين',
        value: '$totalCount',
        icon: Icons.groups_rounded,
        color: colorScheme.primary,
        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderColor: colorScheme.primary.withValues(alpha: 0.25),
      ),
      _StatCardData(
        filterKey: 'tracking_active',
        title: 'التتبع مفعّل',
        value: '$activeTrackingCount',
        icon: Icons.radar_rounded,
        color: colorScheme.primary,
        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderColor: colorScheme.primary.withValues(alpha: 0.25),
      ),
      _StatCardData(
        filterKey: 'inside',
        title: 'داخل الفرع',
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
        title: 'غير متصل / لم يسجل',
        value: '$offlineCount',
        icon: Icons.cloud_off_rounded,
        color: const Color(0xFF757575),
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16.0, 10.0, 16.0, 6.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          if (isNarrow) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: cards.map((c) {
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8.0),
                    child: SizedBox(
                      width: 140,
                      child: _buildCard(c, colorScheme),
                    ),
                  );
                }).toList(),
              ),
            );
          }

          // Single row with all 5 cards side by side
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _buildCard(cards[i], colorScheme)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(_StatCardData data, ColorScheme colorScheme) {
    final isSelected = selectedFilter != null && selectedFilter == data.filterKey;

    return MouseRegion(
      cursor: onFilterChanged != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onFilterChanged != null
            ? () => onFilterChanged!(data.filterKey)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 74,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? data.color.withValues(alpha: 0.16)
                : data.backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? data.color : data.borderColor,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: data.color.withValues(alpha: 0.18),
                      blurRadius: 8,
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
                  Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(data.icon, size: 13, color: data.color),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                        color: isSelected ? data.color : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  data.value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: data.color,
                  ),
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
