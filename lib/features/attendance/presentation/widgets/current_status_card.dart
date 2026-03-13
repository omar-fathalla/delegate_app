import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class CurrentStatusCard extends StatelessWidget {
  final bool isCheckedIn;

  const CurrentStatusCard({super.key, required this.isCheckedIn});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      color: isCheckedIn
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              l10n.currentStatus,
              style: TextStyle(
                color: isCheckedIn
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isCheckedIn ? l10n.online : l10n.offline,
              style: TextStyle(
                color: isCheckedIn
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              DateFormat(
                'EEEE, MMM d, yyyy',
                Localizations.localeOf(context).languageCode,
              ).format(DateTime.now()),
              style: TextStyle(
                color: isCheckedIn
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
