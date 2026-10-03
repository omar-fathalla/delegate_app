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
    this.isSynced = true,
    this.localCheckInTime,
    this.localCheckOutTime,
    this.isAutoCheckOut = false,
    this.autoCheckOutReason,
  });

  /// ما إذا كانت هذه الجلسة قد أغلقت تلقائياً (سواء مسجلة كإغلاق تلقائي أو مر عليها أكثر من 9 ساعات)
  bool get isEffectiveAutoCheckOut =>
      isAutoCheckOut ||
      (checkOutTime == null &&
          DateTime.now().difference(checkInTime) >= const Duration(hours: 9));

  /// وقت الانصراف الفعلي: الانصراف المسجل يدوياً، أو بعد 9 ساعات من الحضور إذا أغلقت تلقائياً
  DateTime? get effectiveCheckOutTime =>
      checkOutTime ??
      (isEffectiveAutoCheckOut
          ? checkInTime.add(const Duration(hours: 9))
          : null);

  /// ما إذا كانت الجلسة نشطة حالياً (حاضر الآن ولم تنته وردية الـ 9 ساعات بعد)
  bool get isActive => checkOutTime == null && !isEffectiveAutoCheckOut;

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
    isSynced,
    localCheckInTime,
    localCheckOutTime,
    isAutoCheckOut,
    autoCheckOutReason,
  ];
}
