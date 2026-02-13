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

class AttendanceHistoryLoaded extends AttendanceState {
  final List<Attendance> history;

  const AttendanceHistoryLoaded({required this.history});

  @override
  List<Object> get props => [history];
}

class AttendanceError extends AttendanceState {
  final String message;

  const AttendanceError({required this.message});

  @override
  List<Object> get props => [message];
}
