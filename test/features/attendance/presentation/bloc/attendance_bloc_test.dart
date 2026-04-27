import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance_pagination_result.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_paginated.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCheckIn extends Mock implements CheckIn {}

class MockCheckOut extends Mock implements CheckOut {}

class MockGetHistory extends Mock implements GetHistory {}

class MockSyncAttendance extends Mock implements SyncAttendance {}

class MockGetHistoryPaginated extends Mock implements GetHistoryPaginated {}

class FakeCheckInParams extends Fake implements CheckInParams {}

class FakeCheckOutParams extends Fake implements CheckOutParams {}

class FakeGetHistoryParams extends Fake implements GetHistoryParams {}

class FakeGetHistoryPaginatedParams extends Fake
    implements GetHistoryPaginatedParams {}

class FakeNoParams extends Fake implements NoParams {}

void main() {
  late AttendanceBloc bloc;
  late MockCheckIn mockCheckIn;
  late MockCheckOut mockCheckOut;
  late MockGetHistory mockGetHistory;
  late MockSyncAttendance mockSyncAttendance;
  late MockGetHistoryPaginated mockGetHistoryPaginated;

  final tAttendance = Attendance(
    id: 'att-1',
    userId: 'user-1',
    organizationId: 'org-1',
    checkInTime: DateTime(2024, 1, 1, 8, 0),
    latitude: 30.0444,
    longitude: 31.2357,
    branchName: 'فرع القاهرة',
  );

  final tAttendanceWithCheckOut = Attendance(
    id: 'att-1',
    userId: 'user-1',
    organizationId: 'org-1',
    checkInTime: DateTime(2024, 1, 1, 8, 0),
    checkOutTime: DateTime(2024, 1, 1, 17, 0),
    latitude: 30.0444,
    longitude: 31.2357,
    branchName: 'فرع القاهرة',
  );

  final tHistory = [tAttendance, tAttendanceWithCheckOut];

  setUpAll(() {
    registerFallbackValue(FakeCheckInParams());
    registerFallbackValue(FakeCheckOutParams());
    registerFallbackValue(FakeGetHistoryParams());
    registerFallbackValue(FakeGetHistoryPaginatedParams());
    registerFallbackValue(FakeNoParams());
  });

  setUp(() {
    mockCheckIn = MockCheckIn();
    mockCheckOut = MockCheckOut();
    mockGetHistory = MockGetHistory();
    mockSyncAttendance = MockSyncAttendance();
    mockGetHistoryPaginated = MockGetHistoryPaginated();
    bloc = AttendanceBloc(
      checkIn: mockCheckIn,
      checkOut: mockCheckOut,
      getHistory: mockGetHistory,
      getHistoryPaginated: mockGetHistoryPaginated,
      syncAttendance: mockSyncAttendance,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be AttendanceInitial', () {
    expect(bloc.state, AttendanceInitial());
  });

  group('CheckInRequested', () {
    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, CheckedIn] on successful check-in',
      build: () {
        when(
          () => mockCheckIn(any()),
        ).thenAnswer((_) async => Right(tAttendance));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const CheckInRequested(
          userId: 'user-1',
          companyId: 'comp-1',
          organizationId: 'org-1',
          deviceInfo: 'Samsung Galaxy',
          lat: 30.0444,
          long: 31.2357,
          branchName: 'فرع القاهرة',
        ),
      ),
      expect: () => [
        AttendanceLoading(),
        AttendanceCheckedIn(attendance: tAttendance),
      ],
      verify: (_) {
        verify(() => mockCheckIn(any())).called(1);
      },
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, Error] when check-in fails (outside geofence)',
      build: () {
        when(() => mockCheckIn(any())).thenAnswer(
          (_) async => const Left(ServerFailure('أنت خارج نطاق الفرع')),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(
        const CheckInRequested(
          userId: 'user-1',
          companyId: 'comp-1',
          organizationId: 'org-1',
          deviceInfo: 'Samsung Galaxy',
          lat: 25.0,
          long: 30.0,
        ),
      ),
      expect: () => [
        AttendanceLoading(),
        const AttendanceError(message: 'أنت خارج نطاق الفرع'),
      ],
    );
  });

  group('CheckOutRequested', () {
    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, CheckedOut] on successful check-out',
      build: () {
        when(
          () => mockCheckOut(any()),
        ).thenAnswer((_) async => Right(tAttendanceWithCheckOut));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const CheckOutRequested(
          attendanceId: 'att-1',
          userId: 'user-1',
          organizationId: 'org-1',
          lat: 30.0444,
          long: 31.2357,
        ),
      ),
      expect: () => [
        AttendanceLoading(),
        AttendanceCheckedOut(attendance: tAttendanceWithCheckOut),
      ],
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, Error] when check-out fails',
      build: () {
        when(() => mockCheckOut(any())).thenAnswer(
          (_) async => const Left(ServerFailure('فشل في تسجيل الخروج')),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(
        const CheckOutRequested(
          attendanceId: 'att-1',
          userId: 'user-1',
          organizationId: 'org-1',
          lat: 30.0444,
          long: 31.2357,
        ),
      ),
      expect: () => [
        AttendanceLoading(),
        const AttendanceError(message: 'فشل في تسجيل الخروج'),
      ],
    );
  });

  group('HistoryRequested', () {
    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, HistoryLoaded] with activeAttendance for active session',
      build: () {
        when(() => mockGetHistoryPaginated(any())).thenAnswer(
          (_) async => Right(
            AttendancePaginationResult(
              items: tHistory,
              hasReachedMax: true,
              lastDoc: null,
            ),
          ),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(
        const HistoryRequested(userId: 'user-1', organizationId: 'org-1'),
      ),
      expect: () => [
        AttendanceLoading(),
        AttendanceHistoryLoaded(
          history: tHistory,
          activeAttendance: tAttendance,
          hasReachedMax: true,
          lastDoc: null,
        ),
      ],
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, HistoryLoaded] with activeAttendance null when no active session',
      build: () {
        when(() => mockGetHistoryPaginated(any())).thenAnswer(
          (_) async => Right(
            AttendancePaginationResult(
              items: [tAttendanceWithCheckOut],
              hasReachedMax: true,
              lastDoc: null,
            ),
          ),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(
        const HistoryRequested(userId: 'user-1', organizationId: 'org-1'),
      ),
      expect: () => [
        AttendanceLoading(),
        AttendanceHistoryLoaded(
          history: [tAttendanceWithCheckOut],
          activeAttendance: null,
          hasReachedMax: true,
          lastDoc: null,
        ),
      ],
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'emits [Loading, Error] when history fetch fails',
      build: () {
        when(
          () => mockGetHistoryPaginated(any()),
        ).thenAnswer((_) async => const Left(ServerFailure('فشل جلب السجل')));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const HistoryRequested(userId: 'user-1', organizationId: 'org-1'),
      ),
      expect: () => [
        AttendanceLoading(),
        const AttendanceError(message: 'فشل جلب السجل'),
      ],
    );
  });

  group('SyncRequested', () {
    blocTest<AttendanceBloc, AttendanceState>(
      'emits SyncStatus changes if current state is AttendanceHistoryLoaded',
      build: () {
        when(
          () => mockSyncAttendance(any()),
        ).thenAnswer((_) async => const Right(null));
        return bloc;
      },
      seed: () => AttendanceHistoryLoaded(
        history: tHistory,
        activeAttendance: tAttendance,
      ),
      act: (bloc) => bloc.add(const SyncRequested()),
      expect: () => [
        AttendanceHistoryLoaded(
          history: tHistory,
          activeAttendance: tAttendance,
          syncStatus: SyncStatus.inProgress,
        ),
        AttendanceHistoryLoaded(
          history: tHistory,
          activeAttendance: tAttendance,
          syncStatus: SyncStatus.success,
        ),
      ],
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'emits SyncStatus failure when sync fails and state is AttendanceHistoryLoaded',
      build: () {
        when(
          () => mockSyncAttendance(any()),
        ).thenAnswer((_) async => const Left(ServerFailure('فشل المزامنة')));
        return bloc;
      },
      seed: () => AttendanceHistoryLoaded(
        history: tHistory,
        activeAttendance: tAttendance,
      ),
      act: (bloc) => bloc.add(const SyncRequested()),
      expect: () => [
        AttendanceHistoryLoaded(
          history: tHistory,
          activeAttendance: tAttendance,
          syncStatus: SyncStatus.inProgress,
        ),
        AttendanceHistoryLoaded(
          history: tHistory,
          activeAttendance: tAttendance,
          syncStatus: SyncStatus.failure,
        ),
      ],
    );
  });
}
