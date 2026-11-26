import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// Asks the delegate to confirm a check-out that comes less than
/// [kEarlyCheckOutConfirmWindow] after check-in. Returns true to proceed.
Future<bool> confirmEarlyCheckOutIfNeeded(
  BuildContext context, {
  required DateTime checkInTime,
  required DateTime now,
}) async {
  final elapsed = now.difference(checkInTime);
  if (elapsed >= kEarlyCheckOutConfirmWindow || elapsed.isNegative) {
    return true;
  }
  final minutes = elapsed.inMinutes < 1 ? 1 : elapsed.inMinutes;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    sheetAnimationStyle: m3SheetAnimation,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => EarlyCheckOutConfirmSheet(minutes: minutes),
  );
  return confirmed == true;
}

class EarlyCheckOutConfirmSheet extends StatelessWidget {
  const EarlyCheckOutConfirmSheet({super.key, required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Symbols.timer_rounded, size: 32, color: cs.primary),
          const SizedBox(height: 16),
          Text(
            l10n.attEarlyCheckOutTitle,
            textAlign: TextAlign.center,
            style: tt.titleLarge?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.attEarlyCheckOutBody(minutes),
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('earlyCheckOutConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.attEarlyCheckOutConfirm),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('earlyCheckOutCancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.attEarlyCheckOutCancel),
          ),
        ],
      ),
    );
  }
}
