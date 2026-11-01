import 'package:material_symbols_icons/symbols.dart';
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
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
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

  List<Attendance> mockPaginatedItems = const [];

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) async {
    final filtered = organizationId.isEmpty
        ? mockPaginatedItems
        : mockPaginatedItems
            .where((a) => a.organizationId == organizationId)
            .toList();
    return Right(filtered);
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
    final filtered = organizationId.isEmpty
        ? mockPaginatedItems
        : mockPaginatedItems
            .where((a) => a.organizationId == organizationId)
            .toList();
    return Right(
      AttendancePaginationResult(
        items: filtered,
        hasReachedMax: true,
        lastDoc: null,
      ),
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

    // Pump for the 2 second delay in BlocProvider create + 1 second in listener
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Verify Previous Month Button
    final prevButtonFinder = find.widgetWithIcon(
      IconButton,
      Symbols.chevron_left_rounded,
    );
    expect(prevButtonFinder, findsOneWidget);

    // Verify Next Month Button
    final nextButtonFinder = find.widgetWithIcon(
      IconButton,
      Symbols.chevron_right_rounded,
    );
    expect(nextButtonFinder, findsOneWidget);
  });

  testWidgets(
    'AttendanceScreen renders distinct chain chips and strips redundant chain prefixes from branch names',
    (WidgetTester tester) async {
      final now = DateTime.now();
      final items = [
        Attendance(
          id: 'att1',
          userId: '1',
          organizationId: '5DE6702w6hFwycJfZyqM',
          branchName: 'جملة ماركت - جناكليس',
          checkInTime: now.subtract(const Duration(hours: 2)),
          checkOutTime: now.subtract(const Duration(hours: 1)),
        ),
        Attendance(
          id: 'att2',
          userId: '1',
          organizationId: '5DE6702w6hFwycJfZyqM',
          branchName: 'جملة ماركت - سان ستيفانو',
          checkInTime: now.subtract(const Duration(hours: 4)),
          checkOutTime: now.subtract(const Duration(hours: 3)),
        ),
        Attendance(
          id: 'att3',
          userId: '1',
          organizationId: 'PiioBFgxaHAeuRdjlDgj',
          branchName: 'City Square',
          checkInTime: now.subtract(const Duration(hours: 6)),
          checkOutTime: now.subtract(const Duration(hours: 5)),
        ),
      ];

      mockAttendanceRepository.mockPaginatedItems = items;

      final multiChainDelegate = Delegate(
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
        organizationUID: 'PiioBFgxaHAeuRdjlDgj',
        organizationName: 'fathalla market',
        allOrganizationNames: const ['fathalla market', 'جملة ماركت'],
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

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AttendanceScreen(
            delegate: multiChainDelegate,
            viewOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Clean branch names without redundant 'جملة ماركت - ' prefix
      expect(find.text('الفرع: جناكليس'), findsOneWidget);
      expect(find.text('الفرع: سان ستيفانو'), findsOneWidget);
      expect(find.text('الفرع: City Square'), findsOneWidget);

      // Normalized Arabic chain chips ('فتح الله ماركت' and 'جملة ماركت')
      expect(find.text('فتح الله ماركت'), findsWidgets);
      expect(find.text('جملة ماركت'), findsWidgets);

      // Tap 'فتح الله ماركت' filter tab in the chain filter bar
      await tester.tap(find.text('فتح الله ماركت').first);
      await tester.pumpAndSettle();

      expect(find.text('الفرع: City Square'), findsOneWidget);
      expect(find.text('الفرع: جناكليس'), findsNothing);
      expect(find.text('الفرع: سان ستيفانو'), findsNothing);

      // Tap 'جملة ماركت' filter tab in the chain filter bar
      await tester.tap(find.text('جملة ماركت').first);
      await tester.pumpAndSettle();

      expect(find.text('الفرع: جناكليس'), findsOneWidget);
      expect(find.text('الفرع: سان ستيفانو'), findsOneWidget);
      expect(find.text('الفرع: City Square'), findsNothing);

      // Tap 'كل السلاسل' to show all chains again
      await tester.tap(find.text('كل السلاسل').first);
      await tester.pumpAndSettle();

      expect(find.text('الفرع: جناكليس'), findsOneWidget);
      expect(find.text('الفرع: سان ستيفانو'), findsOneWidget);
      expect(find.text('الفرع: City Square'), findsOneWidget);
    },
  );

  testWidgets(
    'AttendanceScreen preserves cross-chain records after SyncRequested reload cycle',
    (WidgetTester tester) async {
      final now = DateTime.now();
      mockAttendanceRepository.mockPaginatedItems = [
        Attendance(
          id: 'att1',
          userId: '1',
          organizationId: '5DE6702w6hFwycJfZyqM',
          branchName: 'جملة ماركت - جناكليس',
          checkInTime: now.subtract(const Duration(hours: 2)),
          checkOutTime: now.subtract(const Duration(hours: 1)),
        ),
        Attendance(
          id: 'att3',
          userId: '1',
          organizationId: 'PiioBFgxaHAeuRdjlDgj',
          branchName: 'City Square',
          checkInTime: now.subtract(const Duration(hours: 6)),
          checkOutTime: now.subtract(const Duration(hours: 5)),
        ),
      ];

      final multiChainDelegate = Delegate(
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
        organizationUID: 'PiioBFgxaHAeuRdjlDgj',
        organizationName: 'fathalla market',
        allOrganizationNames: const ['fathalla market', 'جملة ماركت'],
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

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AttendanceScreen(
            delegate: multiChainDelegate,
            viewOnly: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance 2s for SyncRequested + 1s for post-sync HistoryRequested
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('الفرع: جناكليس'), findsOneWidget);
      expect(find.text('الفرع: City Square'), findsOneWidget);
    },
  );
}
