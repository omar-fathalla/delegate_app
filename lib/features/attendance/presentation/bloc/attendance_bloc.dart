import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_paginated.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/core/usecases/usecase.dart';

part 'attendance_event.dart';
part 'attendance_state.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final CheckIn checkIn;
  final CheckOut checkOut;
  final GetHistory getHistory;
  final GetHistoryPaginated getHistoryPaginated;
  final SyncAttendance syncAttendance;

  AttendanceBloc({
    required this.checkIn,
    required this.checkOut,
    required this.getHistory,
    required this.getHistoryPaginated,
    required this.syncAttendance,
  }) : super(AttendanceInitial()) {
    on<CheckInRequested>(_onCheckIn);
    on<CheckOutRequested>(_onCheckOut);
    on<HistoryRequested>(_onGetHistory);
    on<LoadMoreHistoryRequested>(_onLoadMoreHistory);
    on<SyncRequested>(_onSync);
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
    result.fold(
      (failure) => emit(AttendanceError(message: failure.message)),
      (attendance) => emit(AttendanceCheckedIn(attendance: attendance)),
    );
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
    result.fold(
      (failure) => emit(AttendanceError(message: failure.message)),
      (attendance) => emit(AttendanceCheckedOut(attendance: attendance)),
    );
  }

  Future<void> _onGetHistory(
    HistoryRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(AttendanceLoading());

    final failureOrResult = await getHistoryPaginated(
      GetHistoryPaginatedParams(
        userId: event.userId,
        organizationId: event.organizationId,
        nationalityID: event.nationalityID,
        phoneNumber: event.phoneNumber,
        limit: 20,
      ),
    );

    failureOrResult.fold(
      (failure) => emit(AttendanceError(message: failure.message)),
      (result) {
        // Check for any active check-in (checkOutTime is null)
        String? activeAttendanceId;
        try {
          final activeAttendance = result.items.firstWhere(
            (element) => element.checkOutTime == null,
          );
          activeAttendanceId = activeAttendance.id;
        } catch (_) {
          activeAttendanceId = null;
        }

        emit(
          AttendanceHistoryLoaded(
            history: result.items,
            activeAttendanceId: activeAttendanceId,
            lastDoc: result.lastDoc,
            hasReachedMax: result.hasReachedMax,
          ),
        );
      },
    );
  }

  Future<void> _onLoadMoreHistory(
    LoadMoreHistoryRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    final currentState = state;
    if (currentState is AttendanceHistoryLoaded &&
        !currentState.hasReachedMax &&
        !currentState.isLoadingMore) {
      emit(currentState.copyWith(isLoadingMore: true));

      final failureOrResult = await getHistoryPaginated(
        GetHistoryPaginatedParams(
          userId: event.userId,
          organizationId: event.organizationId,
          nationalityID: event.nationalityID,
          phoneNumber: event.phoneNumber,
          limit: 20,
          lastDoc: currentState.lastDoc,
        ),
      );

      failureOrResult.fold(
        (failure) => emit(currentState.copyWith(isLoadingMore: false)),
        (result) {
          final updatedHistory = List<Attendance>.from(currentState.history)
            ..addAll(result.items);

          emit(
            currentState.copyWith(
              history: updatedHistory,
              lastDoc: result.lastDoc,
              hasReachedMax: result.hasReachedMax,
              isLoadingMore: false,
            ),
          );
        },
      );
    }
  }

  Future<void> _onSync(
    SyncRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    final currentState = state;
    if (currentState is AttendanceHistoryLoaded) {
      emit(currentState.copyWith(syncStatus: SyncStatus.inProgress));
    }

    final result = await syncAttendance(NoParams());

    result.fold(
      (failure) {
        if (state is AttendanceHistoryLoaded) {
          emit(
            (state as AttendanceHistoryLoaded).copyWith(
              syncStatus: SyncStatus.failure,
            ),
          );
        }
      },
      (_) {
        if (state is AttendanceHistoryLoaded) {
          emit(
            (state as AttendanceHistoryLoaded).copyWith(
              syncStatus: SyncStatus.success,
            ),
          );
        }
      },
    );
  }
}
