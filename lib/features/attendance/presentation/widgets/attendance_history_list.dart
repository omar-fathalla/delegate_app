import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryList extends StatelessWidget {
  final List<Attendance> history;

  const AttendanceHistoryList({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return M3StaggeredItem(
          index: index,
          child: Card(
            margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Symbols.history_rounded, color: theme.colorScheme.primary),
            ),
            title: Text(DateFormat('yyyy-MM-dd').format(item.checkInTime)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.historyInOut(
                    DateFormat('HH:mm').format(item.checkInTime),
                    item.effectiveCheckOutTime != null
                        ? DateFormat('HH:mm').format(item.effectiveCheckOutTime!)
                        : l10n.active,
                  ),
                ),
                if (item.isEffectiveAutoCheckOut) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.auto_mode_rounded, size: 12, color: Colors.amber[800]),
                        const SizedBox(width: 4),
                        Text(
                          'إغلاق تلقائي (9 س)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            trailing: item.isActive
                ? Icon(
                    Symbols.circle_rounded,
                    color: theme.colorScheme.secondary,
                    size: 12,
                  )
                : Icon(
                    item.isEffectiveAutoCheckOut
                        ? Symbols.auto_mode_rounded
                        : Symbols.check_circle_rounded,
                    color: item.isEffectiveAutoCheckOut
                        ? Colors.amber[800]
                        : theme.colorScheme.outlineVariant,
                    size: 16,
                  ),
            ),
          ),
        );
      },
      );
  }
}
