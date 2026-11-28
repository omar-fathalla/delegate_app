import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
import 'package:delegate_app/features/hr/domain/payroll_penalty_policy.dart';
import 'package:delegate_app/features/hr/domain/services/payroll_day_rules.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:intl/intl.dart';

/// TAS-366: one delegate's payroll for one month.
///
/// Moved as is from the HR payroll screen (`_DelegatePayrollItem`) so the HR
/// screen and the delegate's «مرتبي» screen show the same numbers. The
/// salary dialog on the HR screen still edits the salary fields in place.
class DelegatePayrollItem {
  final Delegate delegate;
  int attendedDays;
  int approvedLeaveDays;

  /// إجازات معتمدة غير مدفوعة (مرضية / طارئة / بدون أجر): تُخصم كالغياب
  int unpaidLeaveDays;
  int absentDays;
  int elapsedWorkingDays;
  int totalWorkMinutes;

  /// TAS-362: days with a forgotten session (no check-out) that count zero
  /// hours until HR sets the check-out. Shown, never used in the sums.
  int forgottenSessionDays;

  // إعدادات الراتب والوردية
  double baseSalary;
  double dailyShiftHours;
  double? customHourlyRate;
  PayrollCalculationMode calculationMode;
  int monthTargetWorkingDays;

  // الجزاءات
  double penaltiesDeductions;
  List<Map<String, dynamic>> appliedPenalties;

  DelegatePayrollItem({
    required this.delegate,
    this.attendedDays = 0,
    this.approvedLeaveDays = 0,
    this.unpaidLeaveDays = 0,
    this.absentDays = 0,
    this.elapsedWorkingDays = 0,
    this.totalWorkMinutes = 0,
    this.forgottenSessionDays = 0,
    this.baseSalary = 3500.0,
    this.dailyShiftHours = 9.0,
    this.customHourlyRate,
    this.calculationMode = PayrollCalculationMode.monthlyWithDeductions,
    this.monthTargetWorkingDays = 26,
    this.penaltiesDeductions = 0.0,
    List<Map<String, dynamic>>? appliedPenalties,
  }) : appliedPenalties = appliedPenalties ?? [];

  /// ساعات العمل الفعلية المنجزة
  double get actualWorkHours => totalWorkMinutes / 60.0;

  /// إجمالي الساعات المستهدفة للوردية في الشهر
  double get targetWorkHours => monthTargetWorkingDays * dailyShiftHours;

  /// أجر الساعة الفعلي المعتمد
  double get effectiveHourlyRate {
    if (customHourlyRate != null && customHourlyRate! > 0) {
      return customHourlyRate!;
    }
    if (targetWorkHours > 0) {
      return baseSalary / targetWorkHours;
    }
    return baseSalary / (26 * 9.0);
  }

  /// أجر اليوم الفعلي المعتمد
  double get effectiveDailyRate => effectiveHourlyRate * dailyShiftHours;

  /// استحقاق ساعات العمل الفعلية
  double get earnedWorkAmount => actualWorkHours * effectiveHourlyRate;

  /// إجمالي ساعات الإجازات المعتمدة
  double get leaveHours => approvedLeaveDays * dailyShiftHours;

  /// استحقاق الإجازات المعتمدة (مدفوعة الأجر)
  double get earnedLeaveAmount => approvedLeaveDays * effectiveDailyRate;

  /// عدد الأيام المستحقة للصرف (أيام الحضور الفعلي + الإجازات الرسمية المعتمدة)
  int get payableDays {
    final days = attendedDays + approvedLeaveDays;
    return days > elapsedWorkingDays ? elapsedWorkingDays : days;
  }

  /// ساعات النقص الناتجة عن أيام الغياب الفعلية
  double get shortfallHours => deductibleDays * dailyShiftHours;

  /// الأيام المخصومة = الغياب + الإجازات غير المدفوعة
  int get deductibleDays => absentDays + unpaidLeaveDays;

  /// قيمة استقطاع أيام الغياب الفعلية (عدد أيام الغياب × أجر اليوم المعتمد)
  double get absenceDeductionAmount {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      // في نمط الساعات يتقاضى فقط ما أنجزه بالساعة ولا يوجد استقطاع غياب إضافي
      return 0.0;
    }
    final deduction = deductibleDays * effectiveDailyRate;
    return deduction > grossEarned ? grossEarned : deduction;
  }

  /// إجمالي الاستحقاق للفترة المنقضية قبل الخصومات (Gross)
  double get grossEarned {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      return earnedWorkAmount + earnedLeaveAmount;
    }
    // في النمط الشهري: استحقاق الفترة المنقضية = أيام العمل المنقضية × أجر اليوم المعتمد
    final earned = elapsedWorkingDays * effectiveDailyRate;
    return earned > baseSalary ? baseSalary : earned;
  }

  /// إجمالي الخصومات (غياب + جزاءات)
  double get totalDeductions => absenceDeductionAmount + penaltiesDeductions;

  /// صافي المستحق الفعلي للصرف (Net Payout)
  /// = الأيام المستحقة الفعلية × أجر اليوم - الجزاءات (النمط الشهري)
  /// = استحقاق الساعات والإجازات - الجزاءات (نمط الساعات)
  double get netSalary {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      final net = (grossEarned - penaltiesDeductions);
      return net > 0 ? net : 0.0;
    } else {
      final earnedDaysAmount = payableDays * effectiveDailyRate;
      final net = (earnedDaysAmount - penaltiesDeductions);
      return net > 0 ? net : 0.0;
    }
  }

  String get formattedTotalHours {
    final h = totalWorkMinutes ~/ 60;
    final m = totalWorkMinutes % 60;
    return '$h س و $m د';
  }
}

/// TAS-366: the single payroll calculation shared by the HR payroll screen
/// and the delegate's «مرتبي» screen. Pure: callers fetch the documents
/// (already scoped to the company) and pass them in.
abstract final class DelegatePayrollCalculator {
  /// Default company policy when `company_payroll_configs/{companyId}` is
  /// missing or unreadable (same values the HR screen always used).
  static CompanyPayrollConfig defaultConfig(String companyUID) => CompanyPayrollConfig(
        companyUID: companyUID,
        calculationMode: PayrollCalculationMode.monthlyWithDeductions,
        defaultDailyShiftHours: 9.0,
        defaultMonthlyBaseSalary: 3500.0,
        defaultMonthlyWorkingDays: 26,
      );

  static DateTime monthStart(DateTime month) => DateTime(month.year, month.month, 1, 0, 0, 0);

  static DateTime monthEnd(DateTime month) =>
      DateTime(month.year, month.month + 1, 1).subtract(const Duration(seconds: 1));

  /// Working days of [month] up to today (Fridays off), capped by the
  /// company's monthly working days. A future month has none.
  static int elapsedWorkingDays({
    required DateTime month,
    required DateTime now,
    required CompanyPayrollConfig config,
  }) {
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final isFutureMonth = DateTime(month.year, month.month).isAfter(DateTime(now.year, now.month));
    if (isFutureMonth) return 0;
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final lastDayToEvaluate = isCurrentMonth ? now.day : nextMonth.subtract(const Duration(days: 1)).day;
    var days = 0;
    for (var day = 1; day <= lastDayToEvaluate; day++) {
      // الجمعة عطلة أسبوعية رسمية لا تحتسب يوم عمل مطلوب للغياب
      if (DateTime(month.year, month.month, day).weekday != DateTime.friday) days++;
    }
    return days > config.defaultMonthlyWorkingDays ? config.defaultMonthlyWorkingDays : days;
  }

  /// The date that decides which month a penalty is deducted in.
  ///
  /// Today: `createdAt` (TAS-308). TAS-365 will add `deductionMonth`; that
  /// change belongs here only, so both screens follow it.
  static DateTime? penaltyPayrollDate(Map<String, dynamic> penalty) {
    final ts = penalty['createdAt'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  /// Penalties deducted in [month]: a deductible status
  /// ([isPayrollDeductiblePenaltyStatus]) and a date inside the month. A
  /// penalty with no date counts in every month (as the HR screen did).
  static List<Map<String, dynamic>> deductiblePenalties(
    Iterable<Map<String, dynamic>> penalties,
    DateTime month,
  ) {
    final start = monthStart(month);
    final end = monthEnd(month);
    final out = <Map<String, dynamic>>[];
    for (final p in penalties) {
      if (!isPayrollDeductiblePenaltyStatus(p['status'])) continue;
      final date = penaltyPayrollDate(p);
      if (date != null && (date.isBefore(start) || date.isAfter(end))) continue;
      out.add(p);
    }
    return out;
  }

  /// Computes one delegate's month.
  ///
  /// [wallet]: the delegate's `user_wallets` doc data, or `{}`. [attendance],
  /// [leaves], [penalties]: this delegate's docs (any month; filtered here).
  /// Only `approved` leaves count.
  static DelegatePayrollItem compute({
    required Delegate delegate,
    required CompanyPayrollConfig config,
    required Map<String, dynamic> wallet,
    required Iterable<Map<String, dynamic>> attendance,
    required Iterable<Map<String, dynamic>> leaves,
    required Iterable<Map<String, dynamic>> penalties,
    required DateTime month,
    required DateTime now,
  }) {
    final start = monthStart(month);
    final end = monthEnd(month);
    final elapsed = elapsedWorkingDays(month: month, now: now, config: config);

    final shiftHours = (wallet['dailyShiftHours'] as num?)?.toDouble() ?? config.defaultDailyShiftHours;

    // Attendance grouped by day.
    final byDay = <String, List<Map<String, dynamic>>>{};
    final dayKey = DateFormat('yyyy-MM-dd');
    for (final log in attendance) {
      final ts = log['timestamp'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      if (date.isBefore(start) || date.isAfter(end)) continue;
      byDay.putIfAbsent(dayKey.format(date), () => []).add(log);
    }

    var attendedDays = 0;
    var totalMins = 0;
    var forgottenDays = 0;
    for (final logs in byDay.values) {
      DateTime? inTime;
      DateTime? outTime;
      // TAS-362: a forgotten session counts zero (from the rule date).
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
      if (inTime == null) continue;
      attendedDays++;
      // الأقل من (الفعلي، الوردية المحددة)، بدون أوفر تايم
      totalMins += PayrollDayRules.paidMinutesForDay(
        checkIn: inTime,
        checkOut: outTime,
        now: now,
        shiftHours: shiftHours,
        forgottenFlag: forgottenFlag,
        manuallyAdjusted: manuallyAdjusted,
      );
      if (MissingCheckOutRule.isUnpaid(
        checkIn: inTime,
        checkOut: outTime,
        flagged: forgottenFlag,
        manuallyAdjusted: manuallyAdjusted,
        now: now,
      )) {
        forgottenDays++;
      }
    }

    // Leaves: annual is paid within the yearly balance; sick / emergency /
    // unpaid are unpaid; late / early leave and hourly requests do not count.
    var unpaidThisMonth = 0;
    var annualThisMonth = 0;
    var annualEarlierThisYear = 0;
    final yearStart = DateTime(start.year);
    for (final leave in leaves) {
      if (leave['status'] != 'approved') continue;
      final days = (leave['daysCount'] as num?)?.toInt() ?? 1;
      final sTs = leave['startDate'];
      final sDate = sTs is Timestamp ? sTs.toDate() : null;
      final inMonth = sDate == null || !(sDate.isBefore(start) || sDate.isAfter(end));
      final category = PayrollDayRules.categorize(leave);
      if (category == PayrollLeaveCategory.notALeaveDay) continue;
      if (category == PayrollLeaveCategory.annual) {
        if (inMonth) {
          annualThisMonth += days;
        } else if (!sDate.isBefore(yearStart) && sDate.isBefore(start)) {
          annualEarlierThisYear += days;
        }
        continue;
      }
      if (!inMonth) continue;
      unpaidThisMonth += days;
    }

    final paidAnnualDays = PayrollDayRules.paidAnnualLeaveDays(
      annualLeaveEnabled: delegate.isAnnualLeaveEnabled,
      annualQuota: delegate.annualLeaveQuota,
      usedEarlierThisYear: annualEarlierThisYear,
      requestedThisMonth: annualThisMonth,
    );
    final unpaidLeaveDays =
        unpaidThisMonth.clamp(0, (elapsed - attendedDays - paidAnnualDays).clamp(0, elapsed));
    final absent = (elapsed - attendedDays - paidAnnualDays - unpaidLeaveDays).clamp(0, elapsed);

    // Salary: wallet override first (monthlyAllocation, then baseSalary),
    // then the company default.
    final alloc = (wallet['monthlyAllocation'] as num?)?.toDouble() ?? 0.0;
    final base = (wallet['baseSalary'] as num?)?.toDouble() ?? 0.0;
    final baseSalary = alloc > 0 ? alloc : (base > 0 ? base : config.defaultMonthlyBaseSalary);
    final customRate = (wallet['customHourlyRate'] as num?)?.toDouble();
    final modeCode = wallet['payrollCalculationMode']?.toString();
    final mode = modeCode != null ? PayrollCalculationModeExt.fromCode(modeCode) : config.calculationMode;

    final applied = deductiblePenalties(penalties, month);
    var totalPenalties = 0.0;
    for (final p in applied) {
      totalPenalties += (p['fineAmount'] as num?)?.toDouble() ?? 0.0;
    }

    return DelegatePayrollItem(
      delegate: delegate,
      attendedDays: attendedDays,
      approvedLeaveDays: paidAnnualDays,
      unpaidLeaveDays: unpaidLeaveDays,
      absentDays: absent,
      elapsedWorkingDays: elapsed,
      totalWorkMinutes: totalMins,
      forgottenSessionDays: forgottenDays,
      baseSalary: baseSalary,
      dailyShiftHours: shiftHours,
      customHourlyRate: customRate,
      calculationMode: mode,
      monthTargetWorkingDays: config.defaultMonthlyWorkingDays,
      penaltiesDeductions: totalPenalties,
      appliedPenalties: applied,
    );
  }
}
