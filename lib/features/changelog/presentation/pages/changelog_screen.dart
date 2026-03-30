import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_bloc.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_event.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_state.dart';

import 'package:delegate_app/main.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:intl/intl.dart';

/// Full-page changelog screen showing all app updates.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ChangelogBloc>()..add(LoadAllUpdates()),
      child: const _ChangelogView(),
    );
  }
}

class _ChangelogView extends StatefulWidget {
  const _ChangelogView();

  @override
  State<_ChangelogView> createState() => _ChangelogViewState();
}

class _ChangelogViewState extends State<_ChangelogView> {
  int? _expandedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(isArabic ? 'سجل التحديثات' : 'Changelog'),
        centerTitle: true,
      ),
      body: BlocBuilder<ChangelogBloc, ChangelogState>(
        builder: (context, state) {
          if (state is ChangelogLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ChangelogError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          context.read<ChangelogBloc>().add(LoadAllUpdates()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is ChangelogAllLoaded) {
            if (state.updates.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 64,
                      color: colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isArabic
                          ? 'لا توجد تحديثات حالياً'
                          : 'No updates available',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.updates.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _buildUpdateCard(context, state.updates[index], index),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildUpdateCard(BuildContext context, AppUpdate update, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;
    final title = isArabic ? update.title : update.titleEn;
    final description = isArabic ? update.description : update.descriptionEn;
    final isExpanded = _expandedIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _expandedIndex = isExpanded ? null : index;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: update.priority == UpdatePriority.critical
              ? Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                  width: 1.5,
                )
              : isExpanded
              ? Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  width: 1,
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
                const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  ..._buildHighlights(context, update),
                  const SizedBox(height: 12),
                  Text(
                    DateFormat(
                      'dd MMM yyyy',
                      isArabic ? 'ar' : 'en',
                    ).format(update.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
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
