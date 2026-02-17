import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAttendanceRepository implements AttendanceRepository {
  @override
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    String? branchName,
  }) async {
    return Right(
      Attendance(
        id: '1',
        userId: userId,
        checkInTime: DateTime.now(),
        checkOutTime: null,
      ),
    );
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long,
  ) async {
    return Right(
      Attendance(
        id: attendanceId,
        userId: 'user1',
        checkInTime: DateTime.now().subtract(const Duration(hours: 1)),
        checkOutTime: DateTime.now(),
      ),
    );
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(String userId) async {
    return const Right([]);
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

    // Register Bloc
    sl.registerFactory(
      () => AttendanceBloc(checkIn: sl(), checkOut: sl(), getHistory: sl()),
    );
  });

  tearDown(() {
    sl.reset();
  });

  const tUser = User(
    id: '1',
    name: 'Test User',
    mobile: '1234567890',
    motherName: 'Mother',
    role: 'delegate',
  );

  testWidgets('AttendanceScreen has accessible icon buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AttendanceScreen(user: tUser)),
    );
    await tester.pumpAndSettle();

    // Verify Previous Month Button
    final prevButtonFinder = find.widgetWithIcon(
      IconButton,
      Icons.arrow_back_ios,
    );
    expect(prevButtonFinder, findsOneWidget);
    final prevButton = tester.widget<IconButton>(prevButtonFinder);
    expect(prevButton.tooltip, 'Previous Month');

    // Verify Next Month Button
    final nextButtonFinder = find.widgetWithIcon(
      IconButton,
      Icons.arrow_forward_ios,
    );
    expect(nextButtonFinder, findsOneWidget);
    final nextButton = tester.widget<IconButton>(nextButtonFinder);
    expect(nextButton.tooltip, 'Next Month');
  });
}
