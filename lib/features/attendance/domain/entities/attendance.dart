import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:equatable/equatable.dart';

class Attendance extends Equatable {
  final String id;
  final String userId;
  final String organizationId; // معرّف المنظمة - لعزل البيانات لكل منظمة
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? branchName;
  final String? branchId;
  final String? branchOrganizationUID;
  final bool isSynced;
  final DateTime? localCheckInTime;
  final DateTime? localCheckOutTime;
  final bool isAutoCheckOut;
  final String? autoCheckOutReason;

  const Attendance({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.checkInTime,
    this.checkOutTime,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.branchName,
    this.branchId,
    this.branchOrganizationUID,
    this.isSynced = true,
    this.localCheckInTime,
    this.localCheckOutTime,
    this.isAutoCheckOut = false,
    this.autoCheckOutReason,
  });

  /// ما إذا كانت هذه الجلسة قد أغلقت تلقائياً (سواء مسجلة كإغلاق تلقائي أو مر عليها أكثر من 11.5 ساعة)
  bool get isEffectiveAutoCheckOut =>
      isAutoCheckOut ||
      (checkOutTime == null &&
          DateTime.now().difference(checkInTime) >= kAttendanceAutoCloseAfter);

  /// TAS-362: جلسة منسية (من تاريخ بداية القاعدة): ساعاتها صفر لحد ما الـ HR
  /// يسجل الانصراف. الانصراف الأوتوماتيك (من التطبيق القديم أو السيرفر)
  /// بيتعامل نفس المعاملة.
  bool get isMissingCheckOut => MissingCheckOutRule.isUnpaid(
        checkIn: checkInTime,
        checkOut: isAutoCheckOut ? null : checkOutTime,
        flagged: isAutoCheckOut,
        now: DateTime.now(),
      );

  /// وقت الانصراف الفعلي: الانصراف المسجل يدوياً، أو بعد 11.5 ساعة من الحضور إذا أغلقت تلقائياً
  DateTime? get effectiveCheckOutTime {
    if (isMissingCheckOut) return null;
    return checkOutTime ??
        (isEffectiveAutoCheckOut ? checkInTime.add(kAttendanceAutoCloseAfter) : null);
  }

  /// ما إذا كانت الجلسة نشطة حالياً (حاضر الآن ولم تنته وردية الـ 11.5 ساعة بعد)
  bool get isActive =>
      checkOutTime == null && !isEffectiveAutoCheckOut && !isMissingCheckOut;

  @override
  List<Object?> get props => [
    id,
    userId,
    organizationId,
    checkInTime,
    checkOutTime,
    latitude,
    longitude,
    imageUrl,
    branchName,
    branchId,
    branchOrganizationUID,
    isSynced,
    localCheckInTime,
    localCheckOutTime,
    isAutoCheckOut,
    autoCheckOutReason,
  ];
}
