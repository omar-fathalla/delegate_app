import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_kpi.dart';
import 'package:flutter_test/flutter_test.dart';

PrivateLabelDay _day(
  int year,
  int month,
  int day, {
  PrivateLabelDayType type = PrivateLabelDayType.worked,
  int audits = 1,
  int rejected = 0,
}) {
  final date = PrivateLabelDates.dayKey(DateTime(year, month, day));
  return PrivateLabelDay(
    id: 'u1_$date',
    organizationUID: 'org',
    companyUID: '',
    delegateUid: 'u1',
    delegateName: 'Test',
    date: date,
    month: PrivateLabelDates.monthKey(year, month),
    type: type,
    auditsCount: type == PrivateLabelDayType.rest ? 0 : audits,
    rejectedCount: rejected,
  );
}

void main() {
  group('PrivateLabelKpi.calculate', () {
    test('perfect month: worked every non-rest day = 100%', () {
      // October 2026 has 31 days; 4 rest days + 27 worked days.
      final days = [
        for (var d = 1; d <= 31; d++)
          _day(2026, 10, d, type: d % 7 == 0 ? PrivateLabelDayType.rest : PrivateLabelDayType.worked),
      ];
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: days,
        restAllowance: 4,
        today: DateTime(2026, 11, 2),
      );
      expect(kpi.daysInMonth, 31);
      expect(kpi.restDaysUsed, 4);
      expect(kpi.achievedDays, 27);
      expect(kpi.scorePercentage, 100);
      expect(kpi.missedDays, 0);
      expect(kpi.todayStatus, PrivateLabelTodayStatus.outsideMonth);
    });

    test('rest days beyond the allowance are not counted', () {
      final days = [
        for (var d = 1; d <= 6; d++) _day(2026, 10, d, type: PrivateLabelDayType.rest),
      ];
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: days,
        restAllowance: 4,
        today: DateTime(2026, 10, 7),
      );
      expect(kpi.restDaysUsed, 6);
      expect(kpi.countedRestDays, 4);
      expect(kpi.remainingRestDays, 0);
      expect(kpi.completedDays, 4);
      expect(kpi.scorePercentage, closeTo(4 / 31 * 100, 0.001));
    });

    test('any upload counts the day regardless of photo count', () {
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: [_day(2026, 10, 1, audits: 1), _day(2026, 10, 2, audits: 25)],
        restAllowance: 4,
        today: DateTime(2026, 10, 3),
      );
      expect(kpi.achievedDays, 2);
    });

    test('a day whose audits are all rejected is not achieved', () {
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: [
          _day(2026, 10, 1, audits: 2, rejected: 2),
          _day(2026, 10, 2, audits: 3, rejected: 1),
        ],
        restAllowance: 4,
        today: DateTime(2026, 10, 3),
      );
      expect(kpi.achievedDays, 1);
      expect(kpi.missedDays, 1);
    });

    test('missed days count only past days, not today', () {
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: [_day(2026, 10, 1), _day(2026, 10, 3, type: PrivateLabelDayType.rest)],
        restAllowance: 4,
        today: DateTime(2026, 10, 7, 14),
      );
      // Days 1..6 checked: 1 achieved, 3 rest → 2,4,5,6 missed.
      expect(kpi.elapsedDays, 7);
      expect(kpi.missedDays, 4);
      expect(kpi.todayStatus, PrivateLabelTodayStatus.pending);
    });

    test('today status reflects achieved / rest', () {
      final today = DateTime(2026, 10, 7, 9);
      final achieved = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: [_day(2026, 10, 7, audits: 3)],
        restAllowance: 4,
        today: today,
      );
      expect(achieved.todayStatus, PrivateLabelTodayStatus.achieved);
      expect(achieved.todayAuditsCount, 3);

      final rest = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: [_day(2026, 10, 7, type: PrivateLabelDayType.rest)],
        restAllowance: 4,
        today: today,
      );
      expect(rest.todayStatus, PrivateLabelTodayStatus.rest);
      expect(rest.scorePercentage, closeTo(1 / 31 * 100, 0.001));
    });

    test('ignores days from other months and de-duplicates (worked wins)', () {
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 10,
        days: [
          _day(2026, 9, 30),
          _day(2026, 11, 1),
          _day(2026, 10, 5, type: PrivateLabelDayType.rest),
          _day(2026, 10, 5),
        ],
        restAllowance: 4,
        today: DateTime(2026, 10, 6),
      );
      expect(kpi.achievedDays, 1);
      expect(kpi.restDaysUsed, 0);
    });

    test('future month has zero elapsed days and no missed days', () {
      final kpi = PrivateLabelKpi.calculate(
        year: 2026,
        month: 11,
        days: [_day(2026, 11, 10, type: PrivateLabelDayType.rest)],
        restAllowance: 5,
        today: DateTime(2026, 10, 7),
      );
      expect(kpi.daysInMonth, 30);
      expect(kpi.elapsedDays, 0);
      expect(kpi.missedDays, 0);
      expect(kpi.remainingRestDays, 4);
      expect(kpi.todayStatus, PrivateLabelTodayStatus.outsideMonth);
    });

    test('February leap year uses 29 days', () {
      final kpi = PrivateLabelKpi.calculate(
        year: 2028,
        month: 2,
        days: const [],
        restAllowance: 4,
        today: DateTime(2028, 3, 1),
      );
      expect(kpi.daysInMonth, 29);
      expect(kpi.missedDays, 29);
      expect(kpi.targetWorkingDays, 25);
    });
  });

  group('PrivateLabelDates', () {
    test('dayKey / monthKey are zero-padded and locale independent', () {
      expect(PrivateLabelDates.dayKey(DateTime(2026, 3, 7)), '2026-03-07');
      expect(PrivateLabelDates.monthKey(2026, 3), '2026-03');
      expect(PrivateLabelDates.dayDocId('u1', '2026-03-07'), 'u1_2026-03-07');
    });
  });
}
