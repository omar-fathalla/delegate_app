import 'package:flutter/material.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:delegate_app/main.dart';
import 'package:intl/intl.dart';

/// A beautiful bottom sheet dialog showing new app updates.
class WhatsNewDialog extends StatelessWidget {
  final List<AppUpdate> updates;
  final VoidCallback onDismiss;

  const WhatsNewDialog({
    super.key,
    required this.updates,
    required this.onDismiss,
  });

  /// Shows the "What's New" bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required List<AppUpdate> updates,
    required VoidCallback onDismiss,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WhatsNewDialog(updates: updates, onDismiss: onDismiss),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic ? 'ما الجديد؟' : "What's New?",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isArabic
                                ? '${updates.length} تحديث جديد'
                                : '${updates.length} new update${updates.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        onDismiss();
                        Navigator.pop(context);
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                color: colorScheme.outlineVariant,
                indent: 24,
                endIndent: 24,
              ),
              // Updates list
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: updates.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _buildUpdateCard(context, updates[index]),
                ),
              ),
              // Dismiss button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      onDismiss();
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      isArabic ? 'فهمت!' : 'Got it!',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpdateCard(BuildContext context, AppUpdate update) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;
    final title = isArabic ? update.title : update.titleEn;
    final description = isArabic ? update.description : update.descriptionEn;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: update.priority == UpdatePriority.critical
            ? Border.all(
                color: colorScheme.error.withValues(alpha: 0.3),
                width: 1.5,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildTypeChip(context, update.type),
              if (update.priority != UpdatePriority.normal) ...[
                const SizedBox(width: 8),
                _buildPriorityChip(context, update.priority),
              ],
              const Spacer(),
              Text(
                'v${update.version}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          ..._buildHighlights(context, update),
          const SizedBox(height: 8),
          Text(
            DateFormat(
              'dd MMM yyyy',
              isArabic ? 'ar' : 'en',
            ).format(update.createdAt),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(BuildContext context, UpdateType type) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    final IconData icon;
    final String label;
    final Color bgColor;
    final Color fgColor;

    switch (type) {
      case UpdateType.feature:
        icon = Icons.rocket_launch_rounded;
        label = isArabic ? 'ميزة جديدة' : 'New Feature';
        bgColor = colorScheme.primaryContainer;
        fgColor = colorScheme.onPrimaryContainer;
      case UpdateType.fix:
        icon = Icons.build_rounded;
        label = isArabic ? 'إصلاح' : 'Bug Fix';
        bgColor = colorScheme.tertiaryContainer;
        fgColor = colorScheme.onTertiaryContainer;
      case UpdateType.improvement:
        icon = Icons.trending_up_rounded;
        label = isArabic ? 'تحسين' : 'Improvement';
        bgColor = colorScheme.secondaryContainer;
        fgColor = colorScheme.onSecondaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildHighlights(BuildContext context, AppUpdate update) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;
    final items = isArabic ? update.highlights : update.highlightsEn;

    if (items.isEmpty) return [];

    return [
      const SizedBox(height: 10),
      ...items.map(
        (item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildPriorityChip(BuildContext context, UpdatePriority priority) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    final String label;
    final Color bgColor;
    final Color fgColor;

    switch (priority) {
      case UpdatePriority.important:
        label = isArabic ? 'مهم' : 'Important';
        bgColor = Colors.orange.shade100;
        fgColor = Colors.orange.shade800;
      case UpdatePriority.critical:
        label = isArabic ? 'هام جداً' : 'Critical';
        bgColor = colorScheme.errorContainer;
        fgColor = colorScheme.onErrorContainer;
      case UpdatePriority.normal:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
}
