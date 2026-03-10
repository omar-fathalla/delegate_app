import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAttendanceRepository extends Mock implements AttendanceRepository {}

void main() {
  late CheckOut usecase;
  late MockAttendanceRepository mockRepository;

  setUp(() {
    mockRepository = MockAttendanceRepository();
    usecase = CheckOut(mockRepository);
  });

  const tAttendanceId = 'att-123';
  const tUserId = 'user-1';
  const tLat = 30.0444;
  const tLong = 31.2357;

  final tAttendance = Attendance(
    id: tAttendanceId,
    userId: tUserId,
    checkInTime: DateTime(2024, 1, 1, 8, 0),
    checkOutTime: DateTime(2024, 1, 1, 17, 0),
    latitude: tLat,
    longitude: tLong,
    branchName: 'Main Branch',
  );

  test('should return attendance with checkOut from repository', () async {
    // arrange
    when(
      () => mockRepository.checkOut(
        any(),
        any(),
        any(),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async => Right(tAttendance));

    // act
    final result = await usecase(
      const CheckOutParams(
        attendanceId: tAttendanceId,
        userId: tUserId,
        lat: tLat,
        long: tLong,
      ),
    );

    // assert
    expect(result, Right(tAttendance));
    verify(
      () => mockRepository.checkOut(
        tAttendanceId,
        tLat,
        tLong,
        userId: tUserId,
      ),
    ).called(1);
  });

  test('should return failure when checkOut fails', () async {
    // arrange
    const tFailure = ServerFailure('فشل تسجيل الخروج');
    when(
      () => mockRepository.checkOut(
        any(),
        any(),
        any(),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async => const Left(tFailure));

    // act
    final result = await usecase(
      const CheckOutParams(
        attendanceId: tAttendanceId,
        userId: tUserId,
        lat: tLat,
        long: tLong,
      ),
    );

    // assert
    expect(result, const Left(tFailure));
  });

  test('CheckOutParams props should contain all fields', () {
    const params = CheckOutParams(
      attendanceId: tAttendanceId,
      userId: tUserId,
      lat: tLat,
      long: tLong,
    );
    expect(params.props, [tAttendanceId, tUserId, tLat, tLong]);
  });
}
