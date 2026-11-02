import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';

/// قواعد احتساب يوم العمل في مسير الرواتب.
///
/// - اليوم المدفوع = الأقل من (الدقائق الفعلية، دقائق الوردية المحددة للعامل).
///   لا يتم احتساب أي وقت إضافي (Overtime).
/// - اليوم المغلق تلقائياً (بدون انصراف) يُحتسب بدقائق الوردية المحددة فقط،
///   ومدة الإغلاق التلقائي (11.5 ساعة) تُستخدم لتوقيت الإغلاق فقط.
/// - الإجازة السنوية المعتمدة تُحتسب يوم عمل مدفوع بالكامل في حدود الرصيد.
class PayrollDayRules {
  const PayrollDayRules._();

  static int shiftMinutes(double shiftHours) =>
      shiftHours <= 0 ? 0 : (shiftHours * 60).round();

  /// الدقائق المدفوعة ليوم واحد.
  static int paidMinutesForDay({
    required DateTime checkIn,
    DateTime? checkOut,
    required DateTime now,
    required double shiftHours,
  }) {
    final cap = shiftMinutes(shiftHours);
    if (checkOut != null) {
      final worked = checkOut.difference(checkIn).inMinutes;
      if (worked <= 0) return 0;
      return worked < cap ? worked : cap;
    }
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

  /// هل طلب الإجازة سنوي بالأيام (وليس بالساعات)؟
  static bool isAnnualDayLeave(Map<String, dynamic> leave) =>
      (leave['type'] ?? 'annual').toString() == 'annual' &&
      leave['isHourly'] != true;
}
