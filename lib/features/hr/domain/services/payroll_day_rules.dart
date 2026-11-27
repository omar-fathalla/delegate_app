import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';

/// قواعد احتساب يوم العمل في مسير الرواتب.
///
/// - اليوم المدفوع = الأقل من (الدقائق الفعلية، دقائق الوردية المحددة للعامل).
///   لا يتم احتساب أي وقت إضافي (Overtime).
/// - اليوم المغلق تلقائياً (بدون انصراف) يُحتسب بدقائق الوردية المحددة فقط،
///   ومدة الإغلاق التلقائي (11.5 ساعة) تُستخدم لتوقيت الإغلاق فقط.
/// - الإجازة السنوية المعتمدة تُحتسب يوم عمل مدفوع بالكامل في حدود الرصيد.
/// - الإجازات المرضية والطارئة وبدون أجر غير مدفوعة وتُخصم كأيام الغياب.
class PayrollDayRules {
  const PayrollDayRules._();

  static int shiftMinutes(double shiftHours) =>
      shiftHours <= 0 ? 0 : (shiftHours * 60).round();

  /// الدقائق المدفوعة ليوم واحد.
  ///
  /// TAS-362: من تاريخ بداية القاعدة ([MissingCheckOutRule])، الجلسة المنسية
  /// (من غير انصراف بعد 11.5 ساعة، أو معلّمة `missingCheckOut`/`isAutoCheckOut`)
  /// بتتحسب صفر لحد ما الـ HR يسجل الانصراف بإيده. قبل التاريخ ده الحساب
  /// القديم (وردية كاملة) زي ما هو.
  static int paidMinutesForDay({
    required DateTime checkIn,
    DateTime? checkOut,
    required DateTime now,
    required double shiftHours,
    bool forgottenFlag = false,
    bool manuallyAdjusted = false,
    DateTime? missingCheckOutRuleFrom,
  }) {
    if (MissingCheckOutRule.isUnpaid(
      checkIn: checkIn,
      checkOut: checkOut,
      flagged: forgottenFlag,
      manuallyAdjusted: manuallyAdjusted,
      now: now,
      ruleFrom: missingCheckOutRuleFrom,
    )) {
      return 0;
    }
    final cap = shiftMinutes(shiftHours);
    if (checkOut != null) {
      final worked = checkOut.difference(checkIn).inMinutes;
      if (worked <= 0) return 0;
      return worked < cap ? worked : cap;
    }
    // TAS-362: under the new rule a session with no check-out is either still
    // running or forgotten; neither is paid yet (no «past day» shortcut, so a
    // shift crossing midnight is not cut at 00:00).
    final ruleStart = missingCheckOutRuleFrom ?? MissingCheckOutRule.from;
    if (ruleStart != null && !checkIn.isBefore(ruleStart)) return 0;
    final isPastDay = checkIn.isBefore(DateTime(now.year, now.month, now.day));
    final isAutoClosed = now.difference(checkIn) >= kAttendanceAutoCloseAfter;
    return (isPastDay || isAutoClosed) ? cap : 0;
  }

  /// عدد أيام الإجازة السنوية المدفوعة لهذا الشهر في حدود الرصيد السنوي.
  static int paidAnnualLeaveDays({
    required bool annualLeaveEnabled,
    required int annualQuota,
    required int usedEarlierThisYear,
    required int requestedThisMonth,
  }) {
    if (!annualLeaveEnabled || annualQuota <= 0 || requestedThisMonth <= 0) {
      return 0;
    }
    final remaining = annualQuota - usedEarlierThisYear;
    if (remaining <= 0) return 0;
    return requestedThisMonth < remaining ? requestedThisMonth : remaining;
  }

  /// تصنيف طلب معتمد في مسير الرواتب.
  static PayrollLeaveCategory categorize(Map<String, dynamic> leave) {
    if (leave['isHourly'] == true) return PayrollLeaveCategory.notALeaveDay;
    switch ((leave['type'] ?? 'annual').toString()) {
      case 'annual':
        return PayrollLeaveCategory.annual;
      case 'sick':
      case 'emergency':
      case 'unpaid':
        return PayrollLeaveCategory.unpaid;
      default:
        // تأخير / انصراف مبكر / أي نوع آخر: ليس يوم إجازة
        return PayrollLeaveCategory.notALeaveDay;
    }
  }

  /// هل طلب الإجازة سنوي بالأيام (وليس بالساعات)؟
  static bool isAnnualDayLeave(Map<String, dynamic> leave) =>
      categorize(leave) == PayrollLeaveCategory.annual;

  /// TAS-313: أيام الإجازة السنوية المعتمدة في سنة معيّنة (التعريف الوحيد للرصيد).
  /// بيحسب الإجازات السنوية بالأيام بس، زي مسير الرواتب. المرضي والطارئ وبدون
  /// مرتب والإجازات بالساعة مابتتخصمش من الرصيد.
  static int usedAnnualLeaveDaysInYear(
    Iterable<Map<String, dynamic>> leaves,
    int year,
  ) {
    var used = 0;
    for (final leave in leaves) {
      if (leave['status'] != 'approved') continue;
      if (!isAnnualDayLeave(leave)) continue;
      final start = leave['startDate'];
      final DateTime? startDate = start is Timestamp
          ? start.toDate()
          : (start is DateTime ? start : null);
      if (startDate == null || startDate.year != year) continue;
      used += (leave['daysCount'] as num?)?.toInt() ?? 1;
    }
    return used;
  }
}

/// فئات الطلبات المعتمدة في مسير الرواتب.
enum PayrollLeaveCategory {
  /// إجازة سنوية: مدفوعة في حدود الرصيد المفعّل، وما زاد يُحتسب غياباً.
  annual,

  /// مرضية / طارئة / بدون أجر: غير مدفوعة، تُخصم كالغياب مع إظهارها كإجازة غير مدفوعة.
  unpaid,

  /// تأخير / انصراف مبكر / إجازة بالساعات: لا تُحتسب يوم إجازة.
  notALeaveDay,
}
