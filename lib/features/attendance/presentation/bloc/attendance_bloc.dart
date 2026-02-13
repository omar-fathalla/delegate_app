import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';

part 'attendance_event.dart';
part 'attendance_state.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final CheckIn checkIn;
  final CheckOut checkOut;
  final GetHistory getHistory;

  // Temporary state to hold current attendance ID for checkout
  // In a real app, strict session management or local storage persistence is needed.
  String? currentAttendanceId;

  AttendanceBloc({
    required this.checkIn,
    required this.checkOut,
    required this.getHistory,
  }) : super(AttendanceInitial()) {
    on<CheckInRequested>(_onCheckIn);
    on<CheckOutRequested>(_onCheckOut);
    on<HistoryRequested>(_onGetHistory);
  }

  Future<void> _onCheckIn(
    CheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoading());
    final result = await checkIn(
      CheckInParams(
        userId: event.userId,
        lat: event.lat,
        long: event.long,
        branchName: event.branchName,
      ),
    );
    result.fold((failure) => emit(AttendanceError(message: failure.message)), (
      attendance,
    ) {
      currentAttendanceId = attendance.id;
      emit(AttendanceCheckedIn(attendance: attendance));
      add(HistoryRequested(userId: event.userId));
    });
  }

  Future<void> _onCheckOut(
    CheckOutRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoading());
    final result = await checkOut(
      CheckOutParams(
        attendanceId: event.attendanceId,
        lat: event.lat,
        long: event.long,
      ),
    );
    result.fold((failure) => emit(AttendanceError(message: failure.message)), (
      attendance,
    ) {
      currentAttendanceId = null;
      emit(AttendanceCheckedOut(attendance: attendance));
      // For check-out, we might need the userId to fetch history.
      // Assuming existing history or passing userId in event would be better.
      // But we don't have userId in CheckOutRequested.
      // We can get it from the attendance object returned!
      add(HistoryRequested(userId: attendance.userId));
    });
  }

  Future<void> _onGetHistory(
    HistoryRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoading());
    final result = await getHistory(GetHistoryParams(userId: event.userId));
    result.fold((failure) => emit(AttendanceError(message: failure.message)), (
      history,
    ) {
      // Check for any active check-in (checkOutTime is null)
      try {
        final activeAttendance = history.firstWhere(
          (element) => element.checkOutTime == null,
        );
        currentAttendanceId = activeAttendance.id;
      } catch (_) {
        currentAttendanceId = null;
      }
      emit(AttendanceHistoryLoaded(history: history));
    });
  }
}
