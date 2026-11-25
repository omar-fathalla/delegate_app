import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_paginated.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/core/services/review_service.dart';
import 'package:delegate_app/core/usecases/usecase.dart';

part 'attendance_event.dart';
part 'attendance_state.dart';

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final CheckIn checkIn;
  final CheckOut checkOut;
  final GetHistory getHistory;
  final GetHistoryPaginated getHistoryPaginated;
  final SyncAttendance syncAttendance;
  final ReviewService? _reviewService;

  static final Map<String, AttendanceHistoryLoaded> _cachedHistoryState = {};
  static void clearCache() => _cachedHistoryState.clear();

  static String _cacheKey(String userId, String organizationId) {
    if (organizationId.trim().isNotEmpty) {
      return '${userId}_${organizationId.trim()}';
    }
    return userId;
  }

  static void _invalidateUserCache(String userId) {
    _cachedHistoryState.removeWhere(
      (k, _) => k == userId || k.startsWith('${userId}_'),
    );
  }

  AttendanceBloc({
    required this.checkIn,
    required this.checkOut,
    required this.getHistory,
    required this.getHistoryPaginated,
    required this.syncAttendance,
    ReviewService? reviewService,
  }) : _reviewService = reviewService,
       super(AttendanceInitial()) {
    // droppable: a second check-in/out while one is running is ignored.
    on<CheckInRequested>(_onCheckIn, transformer: droppable());
    on<CheckOutRequested>(_onCheckOut, transformer: droppable());
    on<HistoryRequested>(_onGetHistory);
    on<LoadMoreHistoryRequested>(_onLoadMoreHistory);
    on<SyncRequested>(_onSync);
    on<CheckOutAndCheckInRequested>(
      _onCheckOutAndCheckIn,
      transformer: droppable(),
    );
  }

  Future<void> _onCheckIn(
    CheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    final cacheKey = _cacheKey(event.userId, event.organizationId);
    final previousLoadedState = state is AttendanceHistoryLoaded
        ? (state as AttendanceHistoryLoaded)
        : _cachedHistoryState[cacheKey];
    final currentHistory = previousLoadedState?.history;

    // Fast memory check: guard against duplicate check-in if there's already an active session
    final activeAttendance =
        previousLoadedState?.activeAttendance ??
        currentHistory?.cast<Attendance?>().firstWhere(
          (a) => a?.checkOutTime == null,
          orElse: () => null,
        );

    if (activeAttendance != null) {
      final now = DateTime.now();
      final isToday =
          activeAttendance.checkInTime.year == now.year &&
          activeAttendance.checkInTime.month == now.month &&
          activeAttendance.checkInTime.day == now.day;

      if (isToday) {
        final activeRef = AttendanceBranchRef.fromAttendanceLog({
          'branchId': activeAttendance.branchId,
          'branchOrganizationUID': activeAttendance.branchOrganizationUID,
          'organizationId': activeAttendance.organizationId,
          'branchName': activeAttendance.branchName,
        });
        final incomingRef = AttendanceBranchRef(
          branchId: event.branchId,
          branchOrganizationUID:
              event.branchOrganizationUID ?? event.organizationId,
          branchName: event.branchName ?? '',
        );
        if (attendanceSameBranch(activeRef, incomingRef)) {
          emit(
            const AttendanceError(
              message:
                  'أنت مسجل حضور بالفعل في هذا الفرع وما زالت الجلسة جارية.',
            ),
          );
          if (previousLoadedState != null) emit(previousLoadedState);
          return;
        } else {
          emit(
            AttendanceError(
              message:
                  'لديك تسجيل حضور نشط في فرع ${activeAttendance.branchName == null ? "آخر" : BranchDisplayCache.instance.displayName(activeAttendance.branchName!)}. يرجى تسجيل الانصراف أولاً.',
            ),
          );
          if (previousLoadedState != null) emit(previousLoadedState);
          return;
        }
      }
    }

    _invalidateUserCache(event.userId);
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
        branchId: event.branchId,
        branchOrganizationUID: event.branchOrganizationUID,
        currentHistory: currentHistory,
        delegateName: event.delegateName,
        phoneNumber: event.phoneNumber,
        companyName: event.companyName,
        personalPhotoURL: event.personalPhotoURL,
      ),
    );
    result.fold(
      (failure) {
        emit(AttendanceError(message: failure.message));
        if (previousLoadedState != null) emit(previousLoadedState);
      },
      (attendance) {
        emit(AttendanceCheckedIn(attendance: attendance));
        _reviewService?.triggerSmartReview();
      },
    );
  }

  Future<void> _onCheckOut(
    CheckOutRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    _invalidateUserCache(event.userId);
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
      _reviewService?.triggerSmartReview();
    });
  }

  Future<void> _onGetHistory(
    HistoryRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    final cacheKey = _cacheKey(event.userId, event.organizationId);
    final cached = _cachedHistoryState[cacheKey];
    if (cached != null) {
      emit(cached);
    } else {
      emit(AttendanceLoading());
    }

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
      (failure) {
        if (cached == null) {
          emit(AttendanceError(message: failure.message));
        }
      },
      (result) {
        // Check for any active check-in (within the 11.5h auto-close window and not checked out)
        Attendance? activeAttendance;
        try {
          activeAttendance = result.items.firstWhere(
            (element) => element.isActive,
          );
        } catch (_) {
          activeAttendance = null;
        }

        final loadedState = AttendanceHistoryLoaded(
          history: result.items,
          activeAttendance: activeAttendance,
          lastDoc: result.lastDoc,
          hasReachedMax: result.hasReachedMax,
        );

        _cachedHistoryState[cacheKey] = loadedState;
        emit(loadedState);
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

  Future<void> _onCheckOutAndCheckIn(
    CheckOutAndCheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    final cacheKey = _cacheKey(event.userId, event.organizationId);
    final previousLoadedState = state is AttendanceHistoryLoaded
        ? (state as AttendanceHistoryLoaded)
        : _cachedHistoryState[cacheKey];
    final currentHistory = previousLoadedState?.history;

    emit(AttendanceLoading());
    // 1. Check out of the old attendance
    final checkOutResult = await checkOut(
      CheckOutParams(
        attendanceId: event.oldAttendanceId,
        userId: event.userId,
        organizationId: event.organizationId,
        lat: event.lat,
        long: event.long,
      ),
    );

    await checkOutResult.fold(
      (failure) async {
        emit(AttendanceError(message: failure.message));
        if (previousLoadedState != null) emit(previousLoadedState);
      },
      (attendance) async {
        // 2. If check-out is successful, proceed to check-in to the new branch.
        // The history captured above still shows the old session as open;
        // hand check-in the closed copy, or its "active session" guard
        // refuses the new check-in we were asked for (TAS-337).
        final historyAfterCheckOut = historyWithCheckedOut(
          currentHistory,
          event.oldAttendanceId,
          attendance,
        );
        final checkInResult = await checkIn(
          CheckInParams(
            userId: event.userId,
            companyId: event.companyId,
            organizationId: event.organizationId,
            deviceInfo: event.deviceInfo,
            lat: event.lat,
            long: event.long,
            branchName: event.branchName,
            branchId: event.branchId,
            branchOrganizationUID: event.branchOrganizationUID,
            currentHistory: historyAfterCheckOut,
            delegateName: event.delegateName,
            phoneNumber: event.phoneNumber,
            companyName: event.companyName,
            personalPhotoURL: event.personalPhotoURL,
          ),
        );

        checkInResult.fold(
          (failure) {
            emit(AttendanceError(message: failure.message));
            if (previousLoadedState != null) emit(previousLoadedState);
          },
          (newAttendance) =>
              emit(AttendanceCheckedIn(attendance: newAttendance)),
        );
      },
    );
  }
}

/// [history] with the session [oldAttendanceId] replaced by its checked-out
/// copy [checkedOut] (TAS-337). A session missing from [history] is left out:
/// check-in then sees no open session, which is the state after check-out.
List<Attendance>? historyWithCheckedOut(
  List<Attendance>? history,
  String oldAttendanceId,
  Attendance checkedOut,
) {
  if (history == null) return null;
  return [
    for (final a in history)
      if (a.id == oldAttendanceId)
        (a.checkOutTime == null && checkedOut.checkOutTime == null)
            ? Attendance(
                id: a.id,
                userId: a.userId,
                organizationId: a.organizationId,
                checkInTime: a.checkInTime,
                checkOutTime: DateTime.now(),
                latitude: a.latitude,
                longitude: a.longitude,
                imageUrl: a.imageUrl,
                branchName: a.branchName,
                branchId: a.branchId,
                branchOrganizationUID: a.branchOrganizationUID,
              )
            : checkedOut
      else
        a,
  ];
}
