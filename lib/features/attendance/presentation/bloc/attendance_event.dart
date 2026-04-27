part of 'attendance_bloc.dart';

abstract class AttendanceEvent extends Equatable {
  const AttendanceEvent();

  @override
  List<Object?> get props => [];
}

class CheckInRequested extends AttendanceEvent {
  final String userId;
  final String companyId;
  final String organizationId;
  final String deviceInfo;
  final double lat;
  final double long;
  final String? branchName;

  const CheckInRequested({
    required this.userId,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    required this.lat,
    required this.long,
    this.branchName,
  });

  @override
  List<Object?> get props => [
    userId,
    companyId,
    organizationId,
    deviceInfo,
    lat,
    long,
    branchName,
  ];
}

class CheckOutRequested extends AttendanceEvent {
  final String attendanceId;
  final String userId;
  final String organizationId;
  final double lat;
  final double long;

  const CheckOutRequested({
    required this.attendanceId,
    required this.userId,
    required this.organizationId,
    required this.lat,
    required this.long,
  });

  @override
  List<Object> get props => [attendanceId, userId, organizationId, lat, long];
}

class HistoryRequested extends AttendanceEvent {
  final String userId;
  final String organizationId;
  final String? nationalityID;
  final String? phoneNumber;

  const HistoryRequested({
    required this.userId,
    required this.organizationId,
    this.nationalityID,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [
    userId,
    organizationId,
    nationalityID,
    phoneNumber,
  ];
}

class LoadMoreHistoryRequested extends AttendanceEvent {
  final String userId;
  final String organizationId;
  final String? nationalityID;
  final String? phoneNumber;

  const LoadMoreHistoryRequested({
    required this.userId,
    required this.organizationId,
    this.nationalityID,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [
    userId,
    organizationId,
    nationalityID,
    phoneNumber,
  ];
}

class SyncRequested extends AttendanceEvent {
  const SyncRequested();
}

class CheckOutAndCheckInRequested extends AttendanceEvent {
  final String oldAttendanceId;
  final String userId;
  final String companyId;
  final String organizationId;
  final String deviceInfo;
  final double lat;
  final double long;
  final String? branchName;

  const CheckOutAndCheckInRequested({
    required this.oldAttendanceId,
    required this.userId,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    required this.lat,
    required this.long,
    this.branchName,
  });

  @override
  List<Object?> get props => [
    oldAttendanceId,
    userId,
    companyId,
    organizationId,
    deviceInfo,
    lat,
    long,
    branchName,
  ];
}
