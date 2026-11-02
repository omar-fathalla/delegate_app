import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';

/// حساب موحّد لملخص الحضور الشهري (أيام الحضور / الغياب / الإجازات).
///
/// يُستخدم في الرئيسية وتبويب الحضور معاً حتى تتطابق الأرقام دائماً.
/// القاعدة: 26 يوم عمل شهرياً، و4 أيام إجازة أسبوعية (يوم لكل 7 أيام فعّالة)
/// مستبعدة من الغياب، والإجازات المعتمدة مستبعدة أيضاً.
class MonthlyAttendanceStats {
  static const int workDaysPerMonth = 26;
  static const int offDaysPerMonth = 4;

  /// عدد الأيام المختلفة التي سُجّل فيها حضور خلال الشهر.
  final int presentDays;

  /// أيام الغياب حتى الآن (للشهر الحالي) أو للشهر كاملاً (للشهر المنتهي).
  final int absentDays;

  /// أيام الإجازات المعتمدة في الشهر.
  final int leaveDays;

  /// أيام العمل المتوقعة حتى الآن بعد استبعاد الإجازات الأسبوعية والمعتمدة.
  final int expectedWorkDays;

  /// مفاتيح الأيام (yyyy-MM-dd) التي فيها حضور، مرتبة.
  final List<String> presentDayKeys;

  const MonthlyAttendanceStats({
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.expectedWorkDays,
    required this.presentDayKeys,
  });

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool isInMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  /// يحسب الملخص لشهر [month] اعتماداً على كل جلسات الشهر [sessions].
  ///
  /// اليوم يُحسب بيوم تسجيل الحضور (جلسة تمتد بعد منتصف الليل تُحسب
  /// ليوم الدخول فقط). [now] هو الوقت الموثوق الحالي، و[createdAt] أقدم
  /// تاريخ تسجيل للمندوب (لاستبعاد الأيام قبل انضمامه).
  static MonthlyAttendanceStats compute({
    required Iterable<Attendance> sessions,
    required DateTime month,
    required DateTime now,
    int approvedLeaveDays = 0,
    DateTime? createdAt,
  }) {
    final keys = <String>{};
    for (final s in sessions) {
      if (isInMonth(s.checkInTime, month)) keys.add(dayKey(s.checkInTime));
    }
    final present = keys.length;
    final leaves = approvedLeaveDays < 0 ? 0 : approvedLeaveDays;

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final monthStart = DateTime(month.year, month.month);
    final currentMonthStart = DateTime(now.year, now.month);

    int lastDay;
    if (monthStart.isAfter(currentMonthStart)) {
      lastDay = 0; // شهر مستقبلي
    } else if (monthStart == currentMonthStart) {
      lastDay = now.day;
    } else {
      lastDay = daysInMonth;
    }

    int firstDay = 1;
    if (createdAt != null) {
      final createdMonth = DateTime(createdAt.year, createdAt.month);
      if (createdMonth.isAfter(monthStart)) {
        lastDay = 0;
      } else if (createdMonth == monthStart && createdAt.day > 1) {
        firstDay = createdAt.day;
      }
    }

    final activeDays = lastDay >= firstDay
        ? (lastDay - firstDay + 1).clamp(0, daysInMonth)
        : 0;
    final offSoFar = (activeDays ~/ 7).clamp(0, offDaysPerMonth);
    final expected = (activeDays - offSoFar - leaves).clamp(
      0,
      workDaysPerMonth,
    );
    final absent = (expected - present).clamp(0, workDaysPerMonth);

    return MonthlyAttendanceStats(
      presentDays: present,
      absentDays: absent,
      leaveDays: leaves,
      expectedWorkDays: expected,
      presentDayKeys: keys.toList()..sort(),
    );
  }
}
