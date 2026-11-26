import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_labels.dart';
import 'package:material_ui/material_ui.dart';

enum _CellState { achieved, rest, missed, today, future, pendingSync }

/// Saturday-first month calendar showing each day's KPI state.
class PrivateLabelMonthCalendar extends StatelessWidget {
  final int year;
  final int month;
  final List<PrivateLabelDay> days;
  final DateTime today;
  final String? selectedDate;
  final ValueChanged<String> onDaySelected;
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  const PrivateLabelMonthCalendar({
    super.key,
    required this.year,
    required this.month,
    required this.days,
    required this.today,
    required this.selectedDate,
    required this.onDaySelected,
    this.onPreviousMonth,
    this.onNextMonth,
  });

  _CellState _stateFor(DateTime date, PrivateLabelDay? d) {
    final todayOnly = PrivateLabelDates.dateOnly(today);
    if (d != null && d.isRest) return _CellState.rest;
    if (d != null && d.isWorkedAchieved) {
      return d.isLocalOnly ? _CellState.pendingSync : _CellState.achieved;
    }
    if (date.isAtSameMomentAs(todayOnly)) return _CellState.today;
    if (date.isAfter(todayOnly)) return _CellState.future;
    return _CellState.missed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final byDate = {for (final d in days) d.date: d};
    final total = PrivateLabelDates.daysInMonth(year, month);
    // Saturday-first offset: Sat=0, Sun=1, Mon=2 ... Fri=6.
    final offset = (DateTime(year, month, 1).weekday + 1) % 7;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'الشهر السابق',
                onPressed: onPreviousMonth,
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  textDirection: TextDirection.ltr,
                ),
              ),
              Expanded(
                child: Text(
                  PrivateLabelLabels.monthTitle(year, month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'الشهر التالي',
                onPressed: onNextMonth,
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: PrivateLabelLabels.weekdaysShort
                .map((w) => Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: offset + total,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox.shrink();
              final dayNumber = index - offset + 1;
              final date = DateTime(year, month, dayNumber);
              final key = PrivateLabelDates.dayKey(date);
              final state = _stateFor(date, byDate[key]);
              return _DayCell(
                day: dayNumber,
                state: state,
                selected: selectedDate == key,
                onTap: () => onDaySelected(key),
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _Legend(color: cs.primary, label: 'محقق'),
              _Legend(color: cs.tertiary, label: 'إجازة'),
              _Legend(color: cs.secondary, label: 'محفوظ لسه'),
              _Legend(color: cs.error, label: 'فايت'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final _CellState state;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.state,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color bg;
    Color fg;
    Color border = Colors.transparent;
    IconData? badge;

    switch (state) {
      case _CellState.achieved:
        bg = cs.primary;
        fg = cs.onPrimary;
      case _CellState.pendingSync:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        badge = Icons.cloud_upload_rounded;
      case _CellState.rest:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        badge = Icons.beach_access_rounded;
      case _CellState.missed:
        bg = cs.errorContainer.withValues(alpha: 0.55);
        fg = cs.onErrorContainer;
      case _CellState.today:
        bg = cs.surfaceContainerHigh;
        fg = cs.primary;
        border = cs.primary;
      case _CellState.future:
        bg = cs.surfaceContainerLow;
        fg = cs.onSurfaceVariant;
    }
    if (selected) border = cs.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: 'يوم $day',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: AppMotionDurations.short4,
            curve: AppMotionCurves.standardDefaultEffects,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: border,
                width: selected ? 2 : 1.4,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (badge != null)
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: Icon(badge, size: 10, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
