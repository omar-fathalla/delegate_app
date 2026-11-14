import 'package:delegate_app/core/utils/date_time_utils.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';

class AttendanceModel extends Attendance {
  const AttendanceModel({
    required super.id,
    required super.userId,
    required super.organizationId,
    required super.checkInTime,
    super.checkOutTime,
    super.latitude,
    super.longitude,
    super.imageUrl,
    super.branchName,
    super.branchId,
    super.branchOrganizationUID,
    super.isSynced = true,
    super.localCheckInTime,
    super.localCheckOutTime,
    super.isAutoCheckOut = false,
    super.autoCheckOutReason,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json, String id) {
    return AttendanceModel(
      id: id,
      userId: json['userId'] ?? json['delegateId'] ?? '',
      organizationId: json['organizationId'] ?? '',
      checkInTime: DateTimeUtils.parseDate(
        json['checkInTime'] ?? json['timestamp'],
      ),
      checkOutTime: DateTimeUtils.parseNullableDate(json['checkOutTime']),
      latitude:
          json['location']?['latitude']?.toDouble() ??
          json['latitude']?.toDouble(),
      longitude:
          json['location']?['longitude']?.toDouble() ??
          json['longitude']?.toDouble(),
      imageUrl: json['imageUrl'],
      branchName: json['branchName'],
      branchId: json['branchId'] as String?,
      branchOrganizationUID:
          (json['branchOrganizationUID'] as String?) ??
          json['organizationId'] as String?,
      isSynced: json['isSynced'] ?? true,
      localCheckInTime: DateTimeUtils.parseNullableDate(
        json['localCheckInTime'],
      ),
      localCheckOutTime: DateTimeUtils.parseNullableDate(
        json['localCheckOutTime'],
      ),
      isAutoCheckOut: json['isAutoCheckOut'] == true,
      autoCheckOutReason: json['autoCheckOutReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'delegateId': userId, // للتوافق مع Firestore
      'organizationId': organizationId,
      'checkInTime': checkInTime.toIso8601String(),
      'timestamp': checkInTime.toIso8601String(), // للتوافق مع Firestore
      'checkOutTime': checkOutTime?.toIso8601String(),
      'location': {'latitude': latitude, 'longitude': longitude},
      'imageUrl': imageUrl,
      'branchName': branchName,
      if (branchId != null) 'branchId': branchId,
      if (branchOrganizationUID != null)
        'branchOrganizationUID': branchOrganizationUID,
      'isSynced': isSynced,
      'localCheckInTime': localCheckInTime?.toIso8601String(),
      'localCheckOutTime': localCheckOutTime?.toIso8601String(),
      'isAutoCheckOut': isAutoCheckOut,
      if (autoCheckOutReason != null) 'autoCheckOutReason': autoCheckOutReason,
    };
  }

  AttendanceModel copyWith({
    String? id,
    String? userId,
    String? organizationId,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    double? latitude,
    double? longitude,
    String? imageUrl,
    String? branchName,
    String? branchId,
    String? branchOrganizationUID,
    bool? isSynced,
    DateTime? localCheckInTime,
    DateTime? localCheckOutTime,
    bool? isAutoCheckOut,
    String? autoCheckOutReason,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      branchName: branchName ?? this.branchName,
      branchId: branchId ?? this.branchId,
      branchOrganizationUID:
          branchOrganizationUID ?? this.branchOrganizationUID,
      isSynced: isSynced ?? this.isSynced,
      localCheckInTime: localCheckInTime ?? this.localCheckInTime,
      localCheckOutTime: localCheckOutTime ?? this.localCheckOutTime,
      isAutoCheckOut: isAutoCheckOut ?? this.isAutoCheckOut,
      autoCheckOutReason: autoCheckOutReason ?? this.autoCheckOutReason,
    );
  }
}
