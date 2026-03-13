/// Integration Tests: Login → Home → Check-in → Check-out flow
///
/// These tests verify the end-to-end flow through BLoC layers
/// using mocked repositories, ensuring the full pipeline works correctly.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockLogin extends Mock implements Login {}
class MockCheckAutoLogin extends Mock implements CheckAutoLogin {}
class MockLogout extends Mock implements Logout {}
class MockCheckIn extends Mock implements CheckIn {}
class MockCheckOut extends Mock implements CheckOut {}
class MockGetHistory extends Mock implements GetHistory {}
class MockSyncAttendance extends Mock implements SyncAttendance {}

class FakeLoginParams extends Fake implements LoginParams {}
class FakeNoParams extends Fake implements NoParams {}
class FakeCheckInParams extends Fake implements CheckInParams {}
class FakeCheckOutParams extends Fake implements CheckOutParams {}
class FakeGetHistoryParams extends Fake implements GetHistoryParams {}

// ── Fixtures ──────────────────────────────────────────────────────────────

final tDelegate = Delegate(
  uid: 'user_1',
  firstName: 'Ahmed',
  middleName: 'Ali',
  lastName: 'Hassan',
  fullName: 'Ahmed Ali Hassan',
  nationalityID: '12345678901234',
  motherName: 'Mother',
  city: 'Cairo',
  phoneNumber: '01234567890',
  gender: DelegateGender.male,
  position: DelegatePosition.promoter,
  birthDate: DateTime(1990, 1, 1),
  organizationUID: 'org1',
  organizationName: 'Org',
  companyUID: 'comp1',
  companyName: 'Comp',
  status: DelegateStatus.active,
  delegatePublicId: 'DEL-1',
  allReceiptCodes: const [],
  createdAt: DateTime(2024, 1, 1),
  createdBy: 'admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
);

final tAttendanceCheckIn = Attendance(
  id: 'att_1',
  userId: 'user_1',
  checkInTime: DateTime(2024, 6, 15, 9, 0),
  checkOutTime: null,
  latitude: 30.0444,
  longitude: 31.2357,
  branchName: 'الفرع الرئيسي',
  isSynced: true,
);

final tAttendanceCheckOut = Attendance(
  id: 'att_1',
  userId: 'user_1',
  checkInTime: DateTime(2024, 6, 15, 9, 0),
  checkOutTime: DateTime(2024, 6, 15, 17, 0),
  latitude: 30.0444,
  longitude: 31.2357,
  branchName: 'الفرع الرئيسي',
  isSynced: true,
);

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(FakeLoginParams());
    registerFallbackValue(FakeNoParams());
    registerFallbackValue(FakeCheckInParams());
    registerFallbackValue(FakeCheckOutParams());
    registerFallbackValue(FakeGetHistoryParams());
  });

  group('Integration: Login Flow', () {
    late MockLogin mockLogin;
    late MockCheckAutoLogin mockCheckAutoLogin;
    late MockLogout mockLogout;

    setUp(() {
      mockLogin = MockLogin();
      mockCheckAutoLogin = MockCheckAutoLogin();
      mockLogout = MockLogout();
    });

    blocTest<AuthBloc, AuthState>(
      'Scenario 1: Successful login transitions to AuthAuthenticated',
      build: () {
        when(() => mockLogin(any()))
            .thenAnswer((_) async => Right(tDelegate));
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
        );
      },
      act: (bloc) => bloc.add(const LoginRequested(
        phoneNumber: '01234567890',
        password: '12345678901234',
      )),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
      verify: (bloc) {
        final state = bloc.state as AuthAuthenticated;
        expect(state.delegate.uid, 'user_1');
        expect(state.delegate.firstName, 'Ahmed');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'Scenario 2: Failed login transitions to AuthError',
      build: () {
        when(() => mockLogin(any())).thenAnswer(
            (_) async => const Left(AuthFailure('كلمة المرور غلط')));
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
        );
      },
      act: (bloc) => bloc.add(const LoginRequested(
        phoneNumber: '01234567890',
        password: 'wrong_password',
      )),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>(),
      ],
      verify: (bloc) {
        final state = bloc.state as AuthError;
        expect(state.message, 'كلمة المرور غلط');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'Scenario 3: Auto-login with cached session',
      build: () {
        when(() => mockCheckAutoLogin(any()))
            .thenAnswer((_) async => Right(tDelegate));
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
        );
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'Scenario 4: Auto-login with no cached session',
      build: () {
        when(() => mockCheckAutoLogin(any()))
            .thenAnswer((_) async => const Right(null));
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
        );
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );
  });

  group('Integration: Attendance Flow (Check-in → Check-out)', () {
    late MockCheckIn mockCheckIn;
    late MockCheckOut mockCheckOut;
    late MockGetHistory mockGetHistory;
    late MockSyncAttendance mockSync;

    setUp(() {
      mockCheckIn = MockCheckIn();
      mockCheckOut = MockCheckOut();
      mockGetHistory = MockGetHistory();
      mockSync = MockSyncAttendance();
    });

    blocTest<AttendanceBloc, AttendanceState>(
      'Scenario 5: Successful check-in',
      build: () {
        when(() => mockCheckIn(any()))
            .thenAnswer((_) async => Right(tAttendanceCheckIn));
        return AttendanceBloc(
          checkIn: mockCheckIn,
          checkOut: mockCheckOut,
          getHistory: mockGetHistory,
          syncAttendance: mockSync,
        );
      },
      act: (bloc) => bloc.add(const CheckInRequested(
        userId: 'user_1',
        companyId: 'comp1',
        organizationId: 'org1',
        deviceInfo: 'Test Device',
        lat: 30.0444,
        long: 31.2357,
        branchName: 'الفرع الرئيسي',
      )),
      expect: () => [
        isA<AttendanceLoading>(),
        isA<AttendanceCheckedIn>(),
      ],
      verify: (bloc) {
        final state = bloc.state as AttendanceCheckedIn;
        expect(state.attendance.id, 'att_1');
        expect(state.attendance.checkOutTime, isNull);
      },
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'Scenario 6: Check-in fails outside geofence',
      build: () {
        when(() => mockCheckIn(any())).thenAnswer((_) async =>
            const Left(ServerFailure(
                'أنت خارج نطاق الفرع (500 متر). النطاق المسموح: 150 متر.')));
        return AttendanceBloc(
          checkIn: mockCheckIn,
          checkOut: mockCheckOut,
          getHistory: mockGetHistory,
          syncAttendance: mockSync,
        );
      },
      act: (bloc) => bloc.add(const CheckInRequested(
        userId: 'user_1',
        companyId: 'comp1',
        organizationId: 'org1',
        deviceInfo: 'Test Device',
        lat: 30.9999,
        long: 31.9999,
        branchName: 'الفرع الرئيسي',
      )),
      expect: () => [
        isA<AttendanceLoading>(),
        isA<AttendanceError>(),
      ],
      verify: (bloc) {
        final state = bloc.state as AttendanceError;
        expect(state.message, contains('خارج نطاق'));
      },
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'Scenario 7: Successful check-out after check-in',
      build: () {
        when(() => mockCheckOut(any()))
            .thenAnswer((_) async => Right(tAttendanceCheckOut));
        return AttendanceBloc(
          checkIn: mockCheckIn,
          checkOut: mockCheckOut,
          getHistory: mockGetHistory,
          syncAttendance: mockSync,
        );
      },
      act: (bloc) => bloc.add(const CheckOutRequested(
        attendanceId: 'att_1',
        userId: 'user_1',
        lat: 30.0444,
        long: 31.2357,
      )),
      expect: () => [
        isA<AttendanceLoading>(),
        isA<AttendanceCheckedOut>(),
      ],
      verify: (bloc) {
        final state = bloc.state as AttendanceCheckedOut;
        expect(state.attendance.checkOutTime, isNotNull);
        expect(state.attendance.id, 'att_1');
      },
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'Scenario 8: History loads correctly after check-in',
      build: () {
        when(() => mockGetHistory(any())).thenAnswer((_) async => Right([
              tAttendanceCheckIn,
            ]));
        return AttendanceBloc(
          checkIn: mockCheckIn,
          checkOut: mockCheckOut,
          getHistory: mockGetHistory,
          syncAttendance: mockSync,
        );
      },
      act: (bloc) => bloc.add(HistoryRequested(userId: 'user_1')),
      expect: () => [
        isA<AttendanceLoading>(),
        isA<AttendanceHistoryLoaded>(),
      ],
      verify: (bloc) {
        final state = bloc.state as AttendanceHistoryLoaded;
        expect(state.history.length, 1);
        expect(state.history.first.id, 'att_1');
        // The active attendance is an open check-in (no checkout time)
        expect(state.activeAttendanceId, 'att_1');
      },
    );

    blocTest<AttendanceBloc, AttendanceState>(
      'Scenario 9: Full Login → CheckIn → CheckOut integration via BLoC chain',
      build: () {
        when(() => mockCheckIn(any()))
            .thenAnswer((_) async => Right(tAttendanceCheckIn));
        when(() => mockCheckOut(any()))
            .thenAnswer((_) async => Right(tAttendanceCheckOut));
        when(() => mockGetHistory(any()))
            .thenAnswer((_) async => Right([tAttendanceCheckOut]));
        return AttendanceBloc(
          checkIn: mockCheckIn,
          checkOut: mockCheckOut,
          getHistory: mockGetHistory,
          syncAttendance: mockSync,
        );
      },
      act: (bloc) async {
        bloc.add(const CheckInRequested(
          userId: 'user_1',
          companyId: 'comp1',
          organizationId: 'org1',
          deviceInfo: 'Device',
          lat: 30.0444,
          long: 31.2357,
          branchName: 'الفرع الرئيسي',
        ));
        await Future.delayed(Duration.zero);
        bloc.add(const CheckOutRequested(
          attendanceId: 'att_1',
          userId: 'user_1',
          lat: 30.0444,
          long: 31.2357,
        ));
        await Future.delayed(Duration.zero);
        bloc.add(HistoryRequested(userId: 'user_1'));
      },
      expect: () => [
        isA<AttendanceLoading>(),
        isA<AttendanceCheckedIn>(),
        isA<AttendanceLoading>(),
        isA<AttendanceCheckedOut>(),
        isA<AttendanceLoading>(),
        isA<AttendanceHistoryLoaded>(),
      ],
    );
  });

  group('Integration: Logout Flow', () {
    late MockLogin mockLogin;
    late MockCheckAutoLogin mockCheckAutoLogin;
    late MockLogout mockLogout;

    setUp(() {
      mockLogin = MockLogin();
      mockCheckAutoLogin = MockCheckAutoLogin();
      mockLogout = MockLogout();
    });

    blocTest<AuthBloc, AuthState>(
      'Scenario 10: Logout clears session and transitions to AuthUnauthenticated',
      build: () {
        when(() => mockLogout(any()))
            .thenAnswer((_) async => const Right(null));
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
        );
      },
      seed: () => AuthAuthenticated(delegate: tDelegate),
      act: (bloc) => bloc.add(LogoutRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );
  });
}
