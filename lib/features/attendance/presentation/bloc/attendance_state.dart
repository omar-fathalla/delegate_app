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
  final dynamic lastDoc;
  final bool isLoadingMore;
  final bool hasReachedMax;

  const AttendanceHistoryLoaded({
    required this.history,
    this.activeAttendanceId,
    this.syncStatus = SyncStatus.initial,
    this.lastDoc,
    this.hasReachedMax = false,
    this.isLoadingMore = false,
  });

  AttendanceHistoryLoaded copyWith({
    List<Attendance>? history,
    String? activeAttendanceId,
    SyncStatus? syncStatus,
    dynamic lastDoc,
    bool? hasReachedMax,
    bool? isLoadingMore,
  }) {
    return AttendanceHistoryLoaded(
      history: history ?? this.history,
      activeAttendanceId: activeAttendanceId ?? this.activeAttendanceId,
      syncStatus: syncStatus ?? this.syncStatus,
      lastDoc: lastDoc ?? this.lastDoc,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [
    history,
    activeAttendanceId,
    syncStatus,
    lastDoc,
    hasReachedMax,
    isLoadingMore,
  ];
}

class AttendanceError extends AttendanceState {
  final String message;

  const AttendanceError({required this.message});

  @override
  List<Object> get props => [message];
}
