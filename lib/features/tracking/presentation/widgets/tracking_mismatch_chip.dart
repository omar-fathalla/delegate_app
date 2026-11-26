import 'package:material_ui/material_ui.dart';

import '../../domain/entities/delegate_tracking_session.dart';

/// TAS-48: small warning chip when the app's inside/outside claim disagrees
/// with the server's distance from the branch (`statusMismatch`). Nothing is
/// shown otherwise. [compact] shows the icon only (table cells).
class TrackingMismatchChip extends StatelessWidget {
  const TrackingMismatchChip({
    super.key,
    required this.session,
    this.compact = false,
  });

  final DelegateTrackingSession session;
  final bool compact;

  static const String label = 'موقع غير مطابق';
  static const String tooltip =
      'حالة الموقع المرسلة من جهاز المندوب لا تطابق حساب الخادم من موقع الفرع';

  @override
  Widget build(BuildContext context) {
    if (!session.statusMismatch) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final color = colorScheme.error;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: label,
        child: Container(
          key: const ValueKey('tracking-mismatch-chip'),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_maybe_rounded, size: 14, color: color),
              if (!compact) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
