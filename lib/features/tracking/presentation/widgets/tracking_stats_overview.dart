import 'package:flutter/material.dart';

class TrackingStatsOverview extends StatelessWidget {
  final int totalCount;
  final int activeTrackingCount;
  final int insideCount;
  final int outsideCount;
  final int offlineCount;

  const TrackingStatsOverview({
    super.key,
    required this.totalCount,
    required this.activeTrackingCount,
    required this.insideCount,
    required this.outsideCount,
    required this.offlineCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16.0, 12.0, 16.0, 6.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'إجمالي الحاضرين',
                  value: '$totalCount',
                  icon: Icons.groups_rounded,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderColor: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'التتبع مفعّل',
                  value: '$activeTrackingCount',
                  icon: Icons.radar_rounded,
                  color: colorScheme.secondary,
                  backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                  borderColor: colorScheme.secondary.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'داخل النطاق',
                  value: '$insideCount',
                  icon: Icons.check_circle_rounded,
                  color: colorScheme.tertiary,
                  backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                  borderColor: colorScheme.tertiary.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'خارج النطاق',
                  value: '$outsideCount',
                  icon: Icons.warning_amber_rounded,
                  color: colorScheme.error,
                  backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.35),
                  borderColor: colorScheme.error.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'غير متصل',
                  value: '$offlineCount',
                  icon: Icons.cloud_off_rounded,
                  color: colorScheme.onSurfaceVariant,
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
