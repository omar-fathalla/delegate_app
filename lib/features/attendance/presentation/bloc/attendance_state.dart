part of 'attendance_bloc.dart';

abstract class AttendanceState extends Equatable {
  const AttendanceState();

  @override
  List<Object?> get props => [];
}

class AttendanceInitial extends AttendanceState {}

class AttendanceLoading extends AttendanceState {}

class AttendanceCheckedIn extends AttendanceState {
  final Attendance attendance;

  const AttendanceCheckedIn({required this.attendance});

  @override
  List<Object> get props => [attendance];
}

class AttendanceCheckedOut extends AttendanceState {
  final Attendance attendance;

  const AttendanceCheckedOut({required this.attendance});

  @override
  List<Object> get props => [attendance];
}

enum SyncStatus { initial, inProgress, success, failure }

class AttendanceHistoryLoaded extends AttendanceState {
  final List<Attendance> history;
  final String? activeAttendanceId;
  final SyncStatus syncStatus;

  const AttendanceHistoryLoaded({
    required this.history,
    this.activeAttendanceId,
    this.syncStatus = SyncStatus.initial,
  });

  AttendanceHistoryLoaded copyWith({
    List<Attendance>? history,
    String? activeAttendanceId,
    SyncStatus? syncStatus,
  }) {
    return AttendanceHistoryLoaded(
      history: history ?? this.history,
      activeAttendanceId: activeAttendanceId ?? this.activeAttendanceId,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  List<Object?> get props => [history, activeAttendanceId, syncStatus];
}

class AttendanceError extends AttendanceState {
  final String message;

  const AttendanceError({required this.message});

  @override
  List<Object> get props => [message];
}
