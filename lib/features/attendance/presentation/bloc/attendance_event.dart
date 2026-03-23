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

  const HistoryRequested({
    required this.userId,
    required this.organizationId,
  });

  @override
  List<Object> get props => [userId, organizationId];
}

class SyncRequested extends AttendanceEvent {
  const SyncRequested();
}
