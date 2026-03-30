import 'package:flutter/material.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// A compact summary card showing task counts by status.
/// Used on [AdminHomeScreen] and [HomeScreen] (Delegate).
class TaskSummaryCard extends StatelessWidget {
  final List<TaskEntity> tasks;
  final bool isLoading;
  final VoidCallback? onTap;

  const TaskSummaryCard({
    super.key,
    required this.tasks,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final pending = tasks.where((t) => t.status == TaskStatus.pending).length;
    final inProgress = tasks
        .where((t) => t.status == TaskStatus.inProgress)
        .length;
    final completed = tasks
        .where((t) => t.status == TaskStatus.completed)
        .length;
    final total = tasks.length;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.task_alt_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.tasksSummary,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Stats row
              if (isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    _StatChip(
                      label: l10n.taskPending,
                      count: pending,
                      color: const Color(0xFFE65100), // deep orange
                      icon: Icons.hourglass_top_rounded,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: l10n.taskInProgress,
                      count: inProgress,
                      color: const Color(0xFF1565C0), // blue
                      icon: Icons.autorenew_rounded,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: l10n.taskCompleted,
                      count: completed,
                      color: const Color(0xFF2E7D32), // green
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: l10n.total,
                      count: total,
                      color: theme.colorScheme.primary,
                      icon: Icons.assignment_rounded,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
