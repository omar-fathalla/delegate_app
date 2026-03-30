import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAttendanceRepository extends Mock implements AttendanceRepository {}

void main() {
  late GetHistory usecase;
  late MockAttendanceRepository mockRepository;

  setUp(() {
    mockRepository = MockAttendanceRepository();
    usecase = GetHistory(mockRepository);
  });

  const tUserId = 'user-1';
  const tOrganizationId = 'org-1';

  final tAttendanceList = [
    Attendance(
      id: '1',
      userId: tUserId,
      organizationId: tOrganizationId,
      checkInTime: DateTime(2024, 1, 1, 8, 0),
      checkOutTime: DateTime(2024, 1, 1, 17, 0),
      latitude: 30.0,
      longitude: 31.0,
      branchName: 'Branch A',
    ),
    Attendance(
      id: '2',
      userId: tUserId,
      organizationId: tOrganizationId,
      checkInTime: DateTime(2024, 1, 2, 8, 0),
      latitude: 30.0,
      longitude: 31.0,
      branchName: 'Branch B',
    ),
  ];

  test('should return attendance history from repository', () async {
    // arrange
    when(
      () => mockRepository.getHistory(any(), any()),
    ).thenAnswer((_) async => Right(tAttendanceList));

    // act
    final result = await usecase(
      const GetHistoryParams(userId: tUserId, organizationId: tOrganizationId),
    );

    // assert
    expect(result, Right(tAttendanceList));
    verify(() => mockRepository.getHistory(tUserId, tOrganizationId)).called(1);
  });

  test('should return empty list when no history', () async {
    // arrange
    when(
      () => mockRepository.getHistory(any(), any()),
    ).thenAnswer((_) async => const Right([]));

    // act
    final result = await usecase(
      const GetHistoryParams(userId: tUserId, organizationId: tOrganizationId),
    );

    // assert
    expect(result, const Right(<Attendance>[]));
  });

  test('should return failure when getHistory fails', () async {
    // arrange
    const tFailure = ServerFailure('فشل جلب السجل');
    when(
      () => mockRepository.getHistory(any(), any()),
    ).thenAnswer((_) async => const Left(tFailure));

    // act
    final result = await usecase(
      const GetHistoryParams(userId: tUserId, organizationId: tOrganizationId),
    );

    // assert
    expect(result, const Left(tFailure));
  });

  test('GetHistoryParams props should contain userId and organizationId', () {
    const params = GetHistoryParams(
      userId: tUserId,
      organizationId: tOrganizationId,
    );
    expect(params.props, [tUserId, tOrganizationId]);
  });
}
