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
import 'package:delegate_app/features/attendance/domain/usecases/get_history_for_month.dart';
import 'package:delegate_app/features/attendance/domain/monthly_attendance_stats.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart'; // Import Delegate
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

class MockAttendanceRepository implements AttendanceRepository {
  @override
  @override
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
    String? branchId,
    String? branchOrganizationUID,
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
    Map<String, dynamic>? qrProof,
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

  /// When set, the paginated history returns only the newest [pageLimit]
  /// sessions (simulates the first page before any scroll).
  int? pageLimit;

  @override
  Future<Either<Failure, List<Attendance>>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  }) async {
    return Right(
      mockPaginatedItems
          .where(
            (a) =>
                a.checkInTime.year == month.year &&
                a.checkInTime.month == month.month,
          )
          .toList(),
    );
  }

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
    if (pageLimit != null && filtered.length > pageLimit!) {
      final sorted = [...filtered]
        ..sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
      return Right(
        AttendancePaginationResult(
          items: sorted.take(pageLimit!).toList(),
          // Reported as the end so the screen doesn't auto-load more; the
          // month summary must still see all sessions via the month query.
          hasReachedMax: true,
          lastDoc: null,
        ),
      );
    }
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
  Future<Either<Failure, void>> syncPendingAttendance({String? userId}) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
    String? branchId,
    String? organizationUID,
  }) async {
    return const Right(null);
  }
}

void main() {
  late MockAttendanceRepository mockAttendanceRepository;

  setUp(() {
    AttendanceBloc.clearCache();
    mockAttendanceRepository = MockAttendanceRepository();
    sl.allowReassignment = true;

    // Register Use Cases with Mock Repository
    sl.registerFactory(() => CheckIn(mockAttendanceRepository));
    sl.registerFactory(() => CheckOut(mockAttendanceRepository));
    sl.registerFactory(() => GetHistory(mockAttendanceRepository));
    sl.registerFactory(() => GetHistoryPaginated(mockAttendanceRepository));
    sl.registerFactory(() => GetHistoryForMonth(mockAttendanceRepository));
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
        localizationsDelegates: appLocalizationsDelegates,
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

      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AttendanceScreen(delegate: multiChainDelegate, viewOnly: false),
        ),
      );
      await tester.pumpAndSettle();
      // viewOnly:false schedules SyncRequested + follow-up HistoryRequested
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Clean branch names without redundant 'جملة ماركت - ' prefix
      expect(find.text('جناكليس'), findsOneWidget);
      expect(find.text('سان ستيفانو'), findsOneWidget);
      expect(find.text('City Square'), findsOneWidget);

      // TAS-387: month progress bar, and the duration as hh:mm (each fake
      // session lasts exactly one hour).
      expect(
        find.byKey(const Key('attendance_month_progress')),
        findsOneWidget,
      );
      expect(find.textContaining('01:00'), findsWidgets);

      // TAS-387: chain then branch filter, as two DropdownMenus.
      expect(find.byKey(const Key('attendance_chain_menu')), findsOneWidget);
      expect(find.byType(DropdownMenu<String>), findsNWidgets(2));

      // Normalized Arabic chain chips ('فتح الله ماركت' and 'جملة ماركت')
      // The session card shows «· chain» next to the branch (TAS-387).
      expect(find.textContaining('فتح الله ماركت'), findsWidgets);
      expect(find.textContaining('جملة ماركت'), findsWidgets);

      // Tap 'فتح الله ماركت' filter tab in the chain filter bar
      // TAS-387: choose the chain from the chain DropdownMenu.
      await tester.tap(find.byKey(const Key('attendance_chain_menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(MenuItemButton),
              matching: find.textContaining('فتح الله ماركت'),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('City Square'), findsOneWidget);
      expect(find.text('جناكليس'), findsNothing);
      expect(find.text('سان ستيفانو'), findsNothing);

      // Tap 'جملة ماركت' filter tab in the chain filter bar
      // TAS-387: choose the chain from the chain DropdownMenu.
      await tester.tap(find.byKey(const Key('attendance_chain_menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(MenuItemButton),
              matching: find.textContaining('جملة ماركت'),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('جناكليس'), findsOneWidget);
      expect(find.text('سان ستيفانو'), findsOneWidget);
      expect(find.text('City Square'), findsNothing);

      // Tap 'كل السلاسل' to show all chains again
      // TAS-387: choose the chain from the chain DropdownMenu.
      await tester.tap(find.byKey(const Key('attendance_chain_menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(MenuItemButton),
              matching: find.textContaining('كل السلاسل'),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('جناكليس'), findsOneWidget);
      expect(find.text('سان ستيفانو'), findsOneWidget);
      expect(find.text('City Square'), findsOneWidget);

      // TAS-352 (C-04): the check-in FAB shrinks while the list scrolls down
      // and comes back on scroll up.
      bool extended() => tester
          .widget<FloatingActionButton>(find.byKey(const Key('attendanceFab')))
          .isExtended;
      await tester.binding.setSurfaceSize(const Size(400, 600));
      await tester.pumpAndSettle();
      expect(extended(), isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(extended(), isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pump();
      expect(extended(), isTrue);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'AttendanceScreen preserves cross-chain records after SyncRequested reload cycle',
    (WidgetTester tester) async {
      // TAS-387: the chain and branch menus are stacked now, so the list
      // starts lower; a tall view keeps every session built.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AttendanceScreen(delegate: multiChainDelegate, viewOnly: false),
        ),
      );
      await tester.pumpAndSettle();

      // Advance 2s for SyncRequested + 1s for post-sync HistoryRequested
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('جناكليس'), findsOneWidget);
      expect(find.text('City Square'), findsOneWidget);
    },
  );

  testWidgets(
    'Month summary uses the whole month, not the first history page (>20 sessions)',
    (WidgetTester tester) async {
      final now = DateTime.now();
      final prevMonth = DateTime(now.year, now.month - 1);
      final daysInPrev = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
      final sessionDays = daysInPrev < 25 ? daysInPrev : 25;
      final items = [
        for (var d = 1; d <= sessionDays; d++)
          Attendance(
            id: 'm$d',
            userId: '1',
            organizationId: 'org1',
            branchName: 'Branch',
            checkInTime: DateTime(prevMonth.year, prevMonth.month, d, 11),
            checkOutTime: DateTime(prevMonth.year, prevMonth.month, d, 17),
          ),
      ];
      mockAttendanceRepository.mockPaginatedItems = items;
      mockAttendanceRepository.pageLimit = 20;

      final oldDelegate = Delegate(
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
        createdAt: DateTime(2020, 1, 1),
        createdBy: 'admin',
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        paymentAmount: 0,
        version: 1,
        documents: const [],
      ); // Same shared calculation the home summary uses.
      final expected = MonthlyAttendanceStats.compute(
        sessions: items,
        month: prevMonth,
        now: now,
        createdAt: oldDelegate.createdAt,
      );
      expect(expected.presentDays, sessionDays);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AttendanceScreen(delegate: oldDelegate, viewOnly: true),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 3));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.tap(
        find.widgetWithIcon(IconButton, Symbols.chevron_left_rounded),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(ValueKey(expected.presentDays)), findsWidgets);
      expect(find.byKey(ValueKey(expected.absentDays)), findsWidgets);
      // The first page alone (20 sessions) would have given a lower count.
      expect(find.byKey(const ValueKey(20)), findsNothing);
    },
  );
}
