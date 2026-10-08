import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'private_label_dates.dart';
import 'private_label_day.dart';

/// Status of today's documentation for the home card.
enum PrivateLabelTodayStatus { pending, achieved, rest, outsideMonth }

/// Monthly Private Label KPI for a single marketer.
///
/// Formula (agreed with the business):
/// `score = (achieved worked days + registered rest days) / days in month × 100`
///
/// Rest days are capped by [restAllowance], so a marketer that works every
/// non-rest day of the month reaches exactly 100%.
class PrivateLabelKpi extends Equatable {
  final int year;
  final int month;
  final int daysInMonth;

  /// Days of the month that have started (including today).
  final int elapsedDays;
  final int achievedDays;
  final int restDaysUsed;
  final int restAllowance;

  /// Past days (before today) with neither an achieved audit nor a rest day.
  final int missedDays;
  final PrivateLabelTodayStatus todayStatus;
  final int todayAuditsCount;

  const PrivateLabelKpi({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.elapsedDays,
    required this.achievedDays,
    required this.restDaysUsed,
    required this.restAllowance,
    required this.missedDays,
    required this.todayStatus,
    required this.todayAuditsCount,
  });

  int get countedRestDays => math.min(restDaysUsed, restAllowance);

  int get completedDays => achievedDays + countedRestDays;

  int get remainingRestDays => math.max(0, restAllowance - restDaysUsed);

  int get targetWorkingDays => math.max(0, daysInMonth - restAllowance);

  double get scorePercentage {
    if (daysInMonth <= 0) return 0;
    return (completedDays / daysInMonth * 100).clamp(0, 100).toDouble();
  }

  /// 0.0 → 1.0 for progress indicators.
  double get progress => scorePercentage / 100;

  static PrivateLabelKpi calculate({
    required int year,
    required int month,
    required List<PrivateLabelDay> days,
    required int restAllowance,
    required DateTime today,
  }) {
    final total = PrivateLabelDates.daysInMonth(year, month);
    final monthKey = PrivateLabelDates.monthKey(year, month);
    final todayOnly = PrivateLabelDates.dateOnly(today);
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month, total);

    final bool todayInMonth =
        !todayOnly.isBefore(monthStart) && !todayOnly.isAfter(monthEnd);

    final int elapsed;
    if (todayOnly.isBefore(monthStart)) {
      elapsed = 0;
    } else if (todayOnly.isAfter(monthEnd)) {
      elapsed = total;
    } else {
      elapsed = todayOnly.day;
    }

    // De-duplicate by date (defensive: one logical day per date).
    final byDate = <String, PrivateLabelDay>{};
    for (final d in days) {
      if (d.month != monthKey) continue;
      final existing = byDate[d.date];
      if (existing == null) {
        byDate[d.date] = d;
      } else {
        // Worked always wins over rest for the same date.
        byDate[d.date] = existing.isRest && !d.isRest ? d : existing;
      }
    }

    final achieved = byDate.values.where((d) => d.isWorkedAchieved).length;
    final restUsed = byDate.values.where((d) => d.isRest).length;

    // Missed: every started day before today that was neither achieved nor rest.
    final pastDaysToCheck = todayInMonth ? elapsed - 1 : elapsed;
    var missed = 0;
    for (var day = 1; day <= pastDaysToCheck; day++) {
      final key = PrivateLabelDates.dayKey(DateTime(year, month, day));
      final d = byDate[key];
      if (d == null || (!d.isRest && !d.isWorkedAchieved)) missed++;
    }

    var todayStatus = PrivateLabelTodayStatus.outsideMonth;
    var todayCount = 0;
    if (todayInMonth) {
      final d = byDate[PrivateLabelDates.dayKey(todayOnly)];
      todayCount = d?.auditsCount ?? 0;
      if (d == null) {
        todayStatus = PrivateLabelTodayStatus.pending;
      } else if (d.isRest) {
        todayStatus = PrivateLabelTodayStatus.rest;
      } else if (d.isWorkedAchieved) {
        todayStatus = PrivateLabelTodayStatus.achieved;
      } else {
        todayStatus = PrivateLabelTodayStatus.pending;
      }
    }

    return PrivateLabelKpi(
      year: year,
      month: month,
      daysInMonth: total,
      elapsedDays: elapsed,
      achievedDays: achieved,
      restDaysUsed: restUsed,
      restAllowance: restAllowance,
      missedDays: missed,
      todayStatus: todayStatus,
      todayAuditsCount: todayCount,
    );
  }

  @override
  List<Object?> get props => [
        year,
        month,
        daysInMonth,
        elapsedDays,
        achievedDays,
        restDaysUsed,
        restAllowance,
        missedDays,
        todayStatus,
        todayAuditsCount,
      ];
}
