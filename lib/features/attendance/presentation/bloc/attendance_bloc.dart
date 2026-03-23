import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/core/usecases/usecase.dart';

part 'attendance_event.dart';
part 'attendance_state.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final CheckIn checkIn;
  final CheckOut checkOut;
  final GetHistory getHistory;
  final SyncAttendance syncAttendance;

  AttendanceBloc({
    required this.checkIn,
    required this.checkOut,
    required this.getHistory,
    required this.syncAttendance,
  }) : super(AttendanceInitial()) {
    on<CheckInRequested>(_onCheckIn);
    on<CheckOutRequested>(_onCheckOut);
    on<HistoryRequested>(_onGetHistory);
    on<SyncRequested>(_onSyncRequested);
  }

  Future<void> _onCheckIn(
    CheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoading());
    final result = await checkIn(
      CheckInParams(
        userId: event.userId,
        companyId: event.companyId,
        organizationId: event.organizationId,
        deviceInfo: event.deviceInfo,
        lat: event.lat,
        long: event.long,
        branchName: event.branchName,
      ),
    );
    result.fold((failure) => emit(AttendanceError(message: failure.message)), (
      attendance,
    ) {
      emit(AttendanceCheckedIn(attendance: attendance));
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
        userId: event.userId,
        organizationId: event.organizationId,
        lat: event.lat,
        long: event.long,
      ),
    );
    result.fold((failure) => emit(AttendanceError(message: failure.message)), (
      attendance,
    ) {
      emit(AttendanceCheckedOut(attendance: attendance));
    });
  }

  Future<void> _onGetHistory(
    HistoryRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoading());
    final result = await getHistory(GetHistoryParams(
      userId: event.userId,
      organizationId: event.organizationId,
    ));
    result.fold((failure) => emit(AttendanceError(message: failure.message)), (
      history,
    ) {
      // Check for any active check-in (checkOutTime is null)
      String? activeAttendanceId;
      try {
        final activeAttendance = history.firstWhere(
          (element) => element.checkOutTime == null,
        );
        activeAttendanceId = activeAttendance.id;
      } catch (_) {
        activeAttendanceId = null;
      }
      emit(
        AttendanceHistoryLoaded(
          history: history,
          activeAttendanceId: activeAttendanceId,
        ),
      );
    });
  }

  Future<void> _onSyncRequested(
    SyncRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    if (state is AttendanceHistoryLoaded) {
      emit(
        (state as AttendanceHistoryLoaded).copyWith(
          syncStatus: SyncStatus.inProgress,
        ),
      );
    }

    final result = await syncAttendance(NoParams());

    if (state is AttendanceHistoryLoaded) {
      result.fold(
        (failure) => emit(
          (state as AttendanceHistoryLoaded).copyWith(
            syncStatus: SyncStatus.failure,
          ),
        ),
        (_) => emit(
          (state as AttendanceHistoryLoaded).copyWith(
            syncStatus: SyncStatus.success,
          ),
        ),
      );
    }
  }
}
