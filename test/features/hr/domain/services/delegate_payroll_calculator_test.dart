// TAS-366: the payroll calculation moved out of the HR screen into
// DelegatePayrollCalculator. These tests pin the numbers:
//  * hand-checked nets for both modes, monthlyAllocation, legacy `approved`
//    penalties, annual leave over the balance and forgotten sessions;
//  * a golden check against a verbatim copy of the old HR loop
//    (`_legacyHrPayroll`, from hr_monthly_payroll_screen.dart @ e398daae),
//    so HR numbers do not change.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
import 'package:delegate_app/features/hr/domain/payroll_penalty_policy.dart';
import 'package:delegate_app/features/hr/domain/services/delegate_payroll_calculator.dart';
import 'package:delegate_app/features/hr/domain/services/payroll_day_rules.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'payroll_fixtures.dart';

final _october = DateTime(2026, 10, 1);
final _now = DateTime(2026, 11, 2, 9);
const _config = CompanyPayrollConfig(companyUID: kFakePayrollCompany);

DelegatePayrollItem _compute({
  required Delegate d,
  Map<String, dynamic> wallet = const {},
  List<Map<String, dynamic>>? attendance,
  List<Map<String, dynamic>>? leaves,
  List<Map<String, dynamic>>? penalties,
  DateTime? month,
  DateTime? now,
  CompanyPayrollConfig config = _config,
}) =>
    DelegatePayrollCalculator.compute(
      delegate: d,
      config: config,
      wallet: wallet,
      attendance: attendance ?? octoberAttendance(d.uid),
      leaves: leaves ?? octoberLeaves(d.uid),
      penalties: penalties ?? octoberPenalties(d.uid),
      month: month ?? _october,
      now: now ?? _now,
    );

void main() {
  setUp(() => MissingCheckOutRule.debugSet(null));
  tearDown(MissingCheckOutRule.debugReset);

  group('hand-checked nets (October 2026: 26 working days)', () {
    test('elapsed working days skip Fridays and cap at the config', () {
      expect(DelegatePayrollCalculator.elapsedWorkingDays(month: _october, now: _now, config: _config), 26);
      // Current month: 1..2 Nov 2026 (Sunday, Monday) = 2 days.
      expect(DelegatePayrollCalculator.elapsedWorkingDays(month: DateTime(2026, 11), now: _now, config: _config), 2);
      expect(DelegatePayrollCalculator.elapsedWorkingDays(month: DateTime(2026, 12), now: _now, config: _config), 0);
      const short = CompanyPayrollConfig(companyUID: kFakePayrollCompany, defaultMonthlyWorkingDays: 22);
      expect(DelegatePayrollCalculator.elapsedWorkingDays(month: _october, now: _now, config: short), 22);
    });

    test('monthly mode: payable days × daily rate − penalties', () {
      final item = _compute(
        d: fakePayrollDelegate(),
        wallet: {'baseSalary': 2600, 'dailyShiftHours': 8},
      );
      // 2600 / (26 × 8) = 12.5/h, 100/day.
      expect(item.effectiveDailyRate, 100);
      expect(item.attendedDays, 3);
      expect(item.approvedLeaveDays, 1, reason: 'quota 2, 1 used in March');
      expect(item.unpaidLeaveDays, 2);
      expect(item.absentDays, 20);
      expect(item.totalWorkMinutes, 480 + 360 + 480);
      expect(item.penaltiesDeductions, 80, reason: 'ISSUED 50 + legacy approved 30');
      expect(item.appliedPenalties, hasLength(2));
      expect(item.netSalary, 320);
    });

    test('monthlyAllocation wins over baseSalary', () {
      final item = _compute(
        d: fakePayrollDelegate(),
        wallet: {'monthlyAllocation': 5200, 'baseSalary': 2600, 'dailyShiftHours': 8},
      );
      expect(item.baseSalary, 5200);
      expect(item.netSalary, 4 * 200 - 80);
    });

    test('no wallet: company default salary and shift', () {
      final item = _compute(d: fakePayrollDelegate());
      expect(item.baseSalary, 3500);
      expect(item.dailyShiftHours, 9);
      expect(item.netSalary, closeTo(4 * 3500 / 26 - 80, 1e-9));
    });

    test('hourly mode: hours × rate + paid leave − penalties', () {
      final item = _compute(
        d: fakePayrollDelegate(uid: 'fake-d2'),
        wallet: {'payrollCalculationMode': 'hourly_rate', 'customHourlyRate': 20},
      );
      // Shift 9h: 8h + 6h + 9h (10h capped) = 23h × 20 = 460; 1 leave day 9h × 20 = 180.
      expect(item.totalWorkMinutes, 1380);
      expect(item.absenceDeductionAmount, 0);
      expect(item.netSalary, 460 + 180 - 80);
    });

    test('annual leave over the balance is not paid', () {
      final item = _compute(
        d: fakePayrollDelegate(annualLeaveQuota: 1),
        wallet: {'baseSalary': 2600, 'dailyShiftHours': 8},
      );
      expect(item.approvedLeaveDays, 0);
      expect(item.netSalary, 300 - 80);
    });

    test('forgotten session: full shift before the rule date, zero after', () {
      MissingCheckOutRule.debugSet(DateTime(2026, 10, 15));
      final d = fakePayrollDelegate();
      final item = _compute(
        d: d,
        wallet: {'baseSalary': 2600, 'dailyShiftHours': 8},
        attendance: [
          checkIn(d.uid, DateTime(2026, 10, 10, 8)), // before the rule: 8h paid
          checkIn(d.uid, DateTime(2026, 10, 20, 8)), // after: 0h, waits for HR
          checkIn(d.uid, DateTime(2026, 10, 21, 8), extra: {'isManuallyAdjusted': true}),
          checkOut(d.uid, DateTime(2026, 10, 21, 12)), // HR fixed it: 4h
        ],
        leaves: const [],
        penalties: const [],
      );
      expect(item.attendedDays, 3);
      expect(item.totalWorkMinutes, 480 + 0 + 240);
      expect(item.forgottenSessionDays, 1);
    });

    test('penalty month filter uses the deductible statuses', () {
      final list = DelegatePayrollCalculator.deductiblePenalties(octoberPenalties('x'), _october);
      expect(list.map((p) => p['fineAmount']), [50, 30]);
    });

    test('TAS-365: an upheld dispute is deducted in its deductionMonth', () {
      final upheld = {
        'status': 'ISSUED',
        'fineAmount': 70,
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 20)),
        'deductionMonth': '2026-10',
      };
      final movedOut = {
        'status': 'ISSUED',
        'fineAmount': 40,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 5)),
        'deductionMonth': '2026-11',
      };
      final disputed = {
        'status': 'DISPUTED',
        'fineAmount': 90,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 6)),
      };
      final oct = DelegatePayrollCalculator.deductiblePenalties([upheld, movedOut, disputed], _october);
      expect(oct.map((p) => p['fineAmount']), [70]);
      final nov = DelegatePayrollCalculator.deductiblePenalties([upheld, movedOut, disputed], DateTime(2026, 11));
      expect(nov.map((p) => p['fineAmount']), [40]);
    });
  });

  group('golden: same numbers as the old HR loop', () {
    final scenarios = <String, Map<String, dynamic>>{
      'monthly + base': {'baseSalary': 2600, 'dailyShiftHours': 8},
      'monthly + allocation': {'monthlyAllocation': 4100, 'dailyShiftHours': 7.5},
      'hourly + custom rate': {'payrollCalculationMode': 'hourly_rate', 'customHourlyRate': 22.5},
      'hourly, derived rate': {'payrollCalculationMode': 'hourly_rate', 'baseSalary': 3900},
      'no wallet': <String, dynamic>{},
    };
    final months = [DateTime(2026, 9), _october, DateTime(2026, 11)];
    final rules = <DateTime?>[null, DateTime(2026, 10, 6)];

    for (final s in scenarios.entries) {
      for (final month in months) {
        for (final rule in rules) {
          test('${s.key} · ${DateFormat('yyyy-MM').format(month)} · rule ${rule ?? 'off'}', () {
            MissingCheckOutRule.debugSet(rule);
            final d = fakePayrollDelegate();
            final attendance = [
              ...octoberAttendance(d.uid),
              checkIn(d.uid, DateTime(2026, 10, 8, 8)), // forgotten
              checkIn(d.uid, DateTime(2026, 11, 1, 8)),
              checkOut(d.uid, DateTime(2026, 11, 1, 13, 30)),
            ];
            final leaves = octoberLeaves(d.uid).where((l) => l['status'] == 'approved').toList();
            final penalties = octoberPenalties(d.uid);

            final legacy = _legacyHrPayroll(
              d: d,
              config: _config,
              wallet: s.value,
              attendance: attendance,
              approvedLeaves: leaves,
              penalties: penalties,
              selectedMonth: month,
              now: _now,
            );
            final item = _compute(
              d: d,
              wallet: s.value,
              attendance: attendance,
              leaves: leaves,
              penalties: penalties,
              month: month,
            );
            expect(item.attendedDays, legacy.attendedDays);
            expect(item.approvedLeaveDays, legacy.approvedLeaveDays);
            expect(item.unpaidLeaveDays, legacy.unpaidLeaveDays);
            expect(item.absentDays, legacy.absentDays);
            expect(item.elapsedWorkingDays, legacy.elapsedWorkingDays);
            expect(item.totalWorkMinutes, legacy.totalWorkMinutes);
            expect(item.baseSalary, legacy.baseSalary);
            expect(item.dailyShiftHours, legacy.dailyShiftHours);
            expect(item.customHourlyRate, legacy.customHourlyRate);
            expect(item.calculationMode, legacy.calculationMode);
            expect(item.penaltiesDeductions, legacy.penaltiesDeductions);
            expect(item.netSalary, legacy.netSalary);
            expect(item.grossEarned, legacy.grossEarned);
            expect(item.absenceDeductionAmount, legacy.absenceDeductionAmount);
          });
        }
      }
    }
  });
}

/// Verbatim copy of the old `_loadPayrollData` steps 4-7 for one delegate
/// (hr_monthly_payroll_screen.dart @ e398daae, lines 271-487). Do not edit:
/// it is the reference the shared calculator must match.
DelegatePayrollItem _legacyHrPayroll({
  required Delegate d,
  required CompanyPayrollConfig config,
  required Map<String, dynamic> wallet,
  required List<Map<String, dynamic>> attendance,
  required List<Map<String, dynamic>> approvedLeaves,
  required List<Map<String, dynamic>> penalties,
  required DateTime selectedMonth,
  required DateTime now,
}) {
  final monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1, 0, 0, 0);
  final nextMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
  final monthEnd = nextMonth.subtract(const Duration(seconds: 1));

  final List<Map<String, dynamic>> delegatePenalties = [];
  for (final data in penalties) {
    if (isPayrollDeductiblePenaltyStatus(data['status'])) {
      final ts = data['createdAt'];
      if (ts is Timestamp) {
        final pDate = ts.toDate();
        if (pDate.isBefore(monthStart) || pDate.isAfter(monthEnd)) continue;
      }
      delegatePenalties.add(data);
    }
  }

  int unpaid = 0;
  int annualThisMonth = 0;
  int annualEarlier = 0;
  final yearStart = DateTime(monthStart.year);
  for (final data in approvedLeaves) {
    final days = (data['daysCount'] as num?)?.toInt() ?? 1;
    final sTs = data['startDate'];
    final sDate = sTs is Timestamp ? sTs.toDate() : null;
    final inMonth = sDate == null || !(sDate.isBefore(monthStart) || sDate.isAfter(monthEnd));
    final category = PayrollDayRules.categorize(data);
    if (category == PayrollLeaveCategory.notALeaveDay) continue;
    if (category == PayrollLeaveCategory.annual) {
      if (inMonth) {
        annualThisMonth += days;
      } else if (!sDate.isBefore(yearStart) && sDate.isBefore(monthStart)) {
        annualEarlier += days;
      }
      continue;
    }
    if (!inMonth) continue;
    unpaid += days;
  }

  final Map<String, List<Map<String, dynamic>>> daysMap = {};
  for (final data in attendance) {
    final ts = data['timestamp'];
    if (ts is Timestamp) {
      final date = ts.toDate();
      if (date.isBefore(monthStart) || date.isAfter(monthEnd)) continue;
      daysMap.putIfAbsent(DateFormat('yyyy-MM-dd').format(date), () => []).add(data);
    }
  }

  final isCurrentMonth = selectedMonth.year == now.year && selectedMonth.month == now.month;
  final isFutureMonth = selectedMonth.isAfter(DateTime(now.year, now.month));
  int elapsedWorkingDays = 0;
  if (!isFutureMonth) {
    final int lastDayToEvaluate = isCurrentMonth ? now.day : nextMonth.subtract(const Duration(days: 1)).day;
    for (int day = 1; day <= lastDayToEvaluate; day++) {
      final dt = DateTime(selectedMonth.year, selectedMonth.month, day);
      if (dt.weekday != DateTime.friday) elapsedWorkingDays++;
    }
    if (elapsedWorkingDays > config.defaultMonthlyWorkingDays) {
      elapsedWorkingDays = config.defaultMonthlyWorkingDays;
    }
  }

  int attendedDaysCount = 0;
  int totalMins = 0;
  final delegateShiftHours = (wallet['dailyShiftHours'] as num?)?.toDouble() ?? config.defaultDailyShiftHours;
  for (final logs in daysMap.values) {
    DateTime? inTime;
    DateTime? outTime;
    final forgottenFlag = MissingCheckOutRule.flaggedIn(logs);
    final manuallyAdjusted = MissingCheckOutRule.adjustedIn(logs);
    for (final log in logs) {
      final type = log['type']?.toString();
      final ts = log['timestamp'];
      DateTime? t;
      if (ts is Timestamp) t = ts.toDate();
      if (type == 'check_in') {
        if (inTime == null || (t != null && t.isBefore(inTime))) inTime = t;
      } else if (type == 'check_out') {
        if (outTime == null || (t != null && t.isAfter(outTime))) outTime = t;
      }
    }
    if (inTime != null) {
      attendedDaysCount++;
      totalMins += PayrollDayRules.paidMinutesForDay(
        checkIn: inTime,
        checkOut: outTime,
        now: now,
        shiftHours: delegateShiftHours,
        forgottenFlag: forgottenFlag,
        manuallyAdjusted: manuallyAdjusted,
      );
    }
  }

  final leaveDays = PayrollDayRules.paidAnnualLeaveDays(
    annualLeaveEnabled: d.isAnnualLeaveEnabled,
    annualQuota: d.annualLeaveQuota,
    usedEarlierThisYear: annualEarlier,
    requestedThisMonth: annualThisMonth,
  );
  final unpaidLeaveDays = unpaid.clamp(0, (elapsedWorkingDays - attendedDaysCount - leaveDays).clamp(0, elapsedWorkingDays));
  final absent = (elapsedWorkingDays - attendedDaysCount - leaveDays - unpaidLeaveDays).clamp(0, elapsedWorkingDays);

  final alloc = (wallet['monthlyAllocation'] as num?)?.toDouble() ?? 0.0;
  final base = (wallet['baseSalary'] as num?)?.toDouble() ?? 0.0;
  final delegateBaseSalary = alloc > 0 ? alloc : (base > 0 ? base : config.defaultMonthlyBaseSalary);
  final customRate = (wallet['customHourlyRate'] as num?)?.toDouble();
  final modeCode = wallet['payrollCalculationMode']?.toString();
  final delegateMode = modeCode != null ? PayrollCalculationModeExt.fromCode(modeCode) : config.calculationMode;

  double totalPenalties = 0.0;
  for (final p in delegatePenalties) {
    totalPenalties += (p['fineAmount'] as num?)?.toDouble() ?? 0.0;
  }

  return DelegatePayrollItem(
    delegate: d,
    attendedDays: attendedDaysCount,
    approvedLeaveDays: leaveDays,
    unpaidLeaveDays: unpaidLeaveDays,
    absentDays: absent,
    elapsedWorkingDays: elapsedWorkingDays,
    totalWorkMinutes: totalMins,
    baseSalary: delegateBaseSalary,
    dailyShiftHours: delegateShiftHours,
    customHourlyRate: customRate,
    calculationMode: delegateMode,
    monthTargetWorkingDays: config.defaultMonthlyWorkingDays,
    penaltiesDeductions: totalPenalties,
    appliedPenalties: delegatePenalties,
  );
}
