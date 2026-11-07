/// مدة الإغلاق التلقائي للحضور: إذا لم يسجّل المندوب انصرافاً، يُغلق الحضور
/// تلقائياً بعد هذه المدة من وقت تسجيل الحضور.
const Duration kAttendanceAutoCloseAfter = Duration(hours: 11, minutes: 30);

/// سبب الإغلاق التلقائي المخزَّن مع الجلسة.
const String kAttendanceAutoCloseReasonAr =
    'نهاية شيفت العمل (11.5 ساعة) - إغلاق تلقائي';
