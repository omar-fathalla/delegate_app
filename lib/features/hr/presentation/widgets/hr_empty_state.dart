import 'package:flutter/material.dart';

/// Centered empty state for HR web pages (TAS-143).
///
/// Shows an [icon], a [title], an optional [message] and an optional
/// [action] (for example a `FilledButton` to add the first item or a
/// `TextButton` to clear a filter). Colors and text styles come from the
/// current theme, so it follows light and dark mode.
///
/// ```dart
/// HrEmptyState(
///   icon: Icons.group_off_rounded,
///   title: 'لا يوجد مناديب',
///   message: 'سيظهر المناديب هنا عند إضافتهم.',
/// )
/// ```
class HrEmptyState extends StatelessWidget {
  /// Icon shown above the title, drawn at 48 in `onSurfaceVariant`.
  final IconData icon;

  /// Short headline, styled with `titleMedium`.
  final String title;

  /// Optional explanation under the title, styled with `bodyMedium`.
  final String? message;

  /// Optional widget under the text, usually a button.
  final Widget? action;

  const HrEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
