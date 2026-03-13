import 'package:delegate_app/core/utils/date_time_utils.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';

class AttendanceModel extends Attendance {
  const AttendanceModel({
    required super.id,
    required super.userId,
    required super.checkInTime,
    super.checkOutTime,
    super.latitude,
    super.longitude,
    super.imageUrl,
    super.branchName,
    super.isSynced = true,
    super.localCheckInTime,
    super.localCheckOutTime,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json, String id) {
    return AttendanceModel(
      id: id,
      userId: json['userId'] ?? '',
      checkInTime: DateTimeUtils.parseDate(json['checkInTime']),
      checkOutTime: DateTimeUtils.parseNullableDate(json['checkOutTime']),
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      imageUrl: json['imageUrl'],
      branchName: json['branchName'],
      isSynced: json['isSynced'] ?? true,
      localCheckInTime: DateTimeUtils.parseNullableDate(json['localCheckInTime']),
      localCheckOutTime: DateTimeUtils.parseNullableDate(json['localCheckOutTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'checkInTime': checkInTime.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'imageUrl': imageUrl,
      'branchName': branchName,
      'isSynced': isSynced,
      'localCheckInTime': localCheckInTime?.toIso8601String(),
      'localCheckOutTime': localCheckOutTime?.toIso8601String(),
    };
  }

  AttendanceModel copyWith({
    String? id,
    String? userId,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    double? latitude,
    double? longitude,
    String? imageUrl,
    String? branchName,
    bool? isSynced,
    DateTime? localCheckInTime,
    DateTime? localCheckOutTime,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      branchName: branchName ?? this.branchName,
      isSynced: isSynced ?? this.isSynced,
      localCheckInTime: localCheckInTime ?? this.localCheckInTime,
      localCheckOutTime: localCheckOutTime ?? this.localCheckOutTime,
    );
  }
}
