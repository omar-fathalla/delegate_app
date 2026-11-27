import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// **Empty state** (P-06): centered placeholder for empty lists (no
/// products, empty cart, no photos this month), and for a load that failed
/// with a retry action. Moved into the kit for app screens (TAS-387).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(TashilSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: TashilSpacing.md),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: TashilSpacing.xs),
            Text(
              message!,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: TashilSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
