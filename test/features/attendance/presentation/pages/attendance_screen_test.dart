import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance_pagination_result.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_paginated.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart'; // Import Delegate
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAttendanceRepository implements AttendanceRepository {
  @override
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
  }) async {
    return Right(
      Attendance(
        id: '1',
        userId: userId,
        organizationId: organizationId,
        checkInTime: DateTime.now(),
        checkOutTime: null,
      ),
    );
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long, {
    required String userId,
    required String organizationId,
  }) async {
    return Right(
      Attendance(
        id: attendanceId,
        userId: 'user1',
        organizationId: organizationId,
        checkInTime: DateTime.now().subtract(const Duration(hours: 1)),
        checkOutTime: DateTime.now(),
      ),
    );
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, AttendancePaginationResult>> getHistoryPaginated(
    String userId,
    String organizationId, {
    int limit = 20,
    String? nationalityID,
    String? phoneNumber,
    dynamic lastDoc,
  }) async {
    return const Right(
      AttendancePaginationResult(items: [], hasReachedMax: true, lastDoc: null),
    );
  }

  @override
  Future<Either<Failure, Attendance?>> findActiveAttendance(
    String userId,
    String organizationId,
  ) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> syncPendingAttendance() async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
  }) async {
    return const Right(null);
  }
}

void main() {
  late MockAttendanceRepository mockAttendanceRepository;

  setUp(() {
    mockAttendanceRepository = MockAttendanceRepository();
    sl.allowReassignment = true;

    // Register Use Cases with Mock Repository
    sl.registerFactory(() => CheckIn(mockAttendanceRepository));
    sl.registerFactory(() => CheckOut(mockAttendanceRepository));
    sl.registerFactory(() => GetHistory(mockAttendanceRepository));
    sl.registerFactory(() => GetHistoryPaginated(mockAttendanceRepository));
    sl.registerFactory(() => SyncAttendance(mockAttendanceRepository));

    // Register Bloc
    sl.registerFactory(
      () => AttendanceBloc(
        checkIn: sl(),
        checkOut: sl(),
        getHistory: sl(),
        getHistoryPaginated: sl(),
        syncAttendance: sl(),
      ),
    );
  });

  tearDown(() {
    sl.reset();
  });

  // Create tDelegate instead of tUser
  final tDelegate = Delegate(
    uid: '1',
    firstName: 'Test',
    middleName: 'User',
    lastName: 'Name',
    fullName: 'Test User Name',
    nationalityID: '1234567890',
    motherName: 'Mother Name',
    city: 'City',
    phoneNumber: '1234567890',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org1',
    organizationName: 'Org Name',
    companyUID: 'comp1',
    companyName: 'Comp Name',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-123',
    allReceiptCodes: const [],
    createdAt: DateTime.now(),
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

  testWidgets('AttendanceScreen has accessible icon buttons', (
    WidgetTester tester,
  ) async {
    // Pass delegate instead of user
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AttendanceScreen(delegate: tDelegate),
      ),
    );
    await tester.pumpAndSettle();

    // Pump for the 1 second delay in AttendanceSyncSuccess listener
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify Previous Month Button
    final prevButtonFinder = find.widgetWithIcon(
      FilledButton,
      Icons.chevron_left_rounded,
    );
    expect(prevButtonFinder, findsOneWidget);

    // Verify Next Month Button
    final nextButtonFinder = find.widgetWithIcon(
      FilledButton,
      Icons.chevron_right_rounded,
    );
    expect(nextButtonFinder, findsOneWidget);
  });
}
