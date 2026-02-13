part of 'attendance_bloc.dart';

abstract class AttendanceEvent extends Equatable {
  const AttendanceEvent();

  @override
  List<Object?> get props => [];
}

class CheckInRequested extends AttendanceEvent {
  final String userId;
  final double lat;
  final double long;
  final String? branchName;

  const CheckInRequested({
    required this.userId,
    required this.lat,
    required this.long,
    this.branchName,
  });

  @override
  List<Object?> get props => [userId, lat, long, branchName];
}

class CheckOutRequested extends AttendanceEvent {
  final String attendanceId;
  final double lat;
  final double long;

  const CheckOutRequested({
    required this.attendanceId,
    required this.lat,
    required this.long,
  });

  @override
  List<Object> get props => [attendanceId, lat, long];
}

class HistoryRequested extends AttendanceEvent {
  final String userId;

  const HistoryRequested({required this.userId});

  @override
  List<Object> get props => [userId];
}
