import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAttendanceRepository extends Mock implements AttendanceRepository {}

void main() {
  late SyncAttendance usecase;
  late MockAttendanceRepository mockRepository;

  setUp(() {
    mockRepository = MockAttendanceRepository();
    usecase = SyncAttendance(mockRepository);
  });

  test('should sync pending attendance successfully', () async {
    // arrange
    when(() => mockRepository.syncPendingAttendance())
        .thenAnswer((_) async => const Right(null));

    // act
    final result = await usecase(NoParams());

    // assert
    expect(result, const Right(null));
    verify(() => mockRepository.syncPendingAttendance()).called(1);
  });

  test('should return failure when sync fails', () async {
    // arrange
    const tFailure = NetworkFailure('لا يوجد اتصال بالإنترنت');
    when(() => mockRepository.syncPendingAttendance())
        .thenAnswer((_) async => const Left(tFailure));

    // act
    final result = await usecase(NoParams());

    // assert
    expect(result, const Left(tFailure));
  });
}
