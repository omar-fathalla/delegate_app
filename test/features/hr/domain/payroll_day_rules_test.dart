import 'package:delegate_app/features/hr/domain/services/payroll_day_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 10, 8);
  final now = DateTime(2026, 11, 2, 9);

  group('paidMinutesForDay', () {
    test('overtime is capped at configured shift (8h)', () {
      expect(
        PayrollDayRules.paidMinutesForDay(
          checkIn: day, checkOut: day.add(const Duration(hours: 10)), now: now, shiftHours: 8),
        480,
      );
    });
    test('short day is paid actual minutes', () {
      expect(
        PayrollDayRules.paidMinutesForDay(
          checkIn: day, checkOut: day.add(const Duration(hours: 6, minutes: 15)), now: now, shiftHours: 9),
        375,
      );
    });
    test('auto-closed past day = configured shift, not 11.5h', () {
      expect(PayrollDayRules.paidMinutesForDay(checkIn: day, now: now, shiftHours: 9), 540);
      expect(PayrollDayRules.paidMinutesForDay(checkIn: day, now: now, shiftHours: 8), 480);
    });
    test('open session today before auto-close = 0', () {
      final today = DateTime(2026, 11, 2, 7);
      expect(PayrollDayRules.paidMinutesForDay(checkIn: today, now: now, shiftHours: 9), 0);
    });
  });

  group('paidAnnualLeaveDays', () {
    test('approved annual leave within balance is fully paid', () {
      expect(
        PayrollDayRules.paidAnnualLeaveDays(
          annualLeaveEnabled: true, annualQuota: 21, usedEarlierThisYear: 5, requestedThisMonth: 2),
        2,
      );
    });
    test('over-balance days are not paid', () {
      expect(
        PayrollDayRules.paidAnnualLeaveDays(
          annualLeaveEnabled: true, annualQuota: 21, usedEarlierThisYear: 20, requestedThisMonth: 3),
        1,
      );
      expect(
        PayrollDayRules.paidAnnualLeaveDays(
          annualLeaveEnabled: true, annualQuota: 21, usedEarlierThisYear: 21, requestedThisMonth: 1),
        0,
      );
    });
    test('annual leave not enabled is not paid', () {
      expect(
        PayrollDayRules.paidAnnualLeaveDays(
          annualLeaveEnabled: false, annualQuota: 21, usedEarlierThisYear: 0, requestedThisMonth: 2),
        0,
      );
    });
    test('only day-based annual requests count as annual', () {
      expect(PayrollDayRules.isAnnualDayLeave({'type': 'annual'}), isTrue);
      expect(PayrollDayRules.isAnnualDayLeave({}), isTrue);
      expect(PayrollDayRules.isAnnualDayLeave({'type': 'annual', 'isHourly': true}), isFalse);
      expect(PayrollDayRules.isAnnualDayLeave({'type': 'sick'}), isFalse);
    });
  });
}
