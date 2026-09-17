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
              child: Icon(Icons.history, color: theme.colorScheme.primary),
            ),
            title: Text(DateFormat('yyyy-MM-dd').format(item.checkInTime)),
            subtitle: Text(
              l10n.historyInOut(
                DateFormat('HH:mm').format(item.checkInTime),
                item.checkOutTime != null
                    ? DateFormat('HH:mm').format(item.checkOutTime!)
                    : l10n.active,
              ),
            ),
            trailing: item.checkOutTime == null
                ? Icon(
                    Icons.circle,
                    color: theme.colorScheme.secondary,
                    size: 12,
                  )
                : Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.outlineVariant,
                    size: 16,
                  ),
            ),
          ),
        );
      },
      );
  }
}
