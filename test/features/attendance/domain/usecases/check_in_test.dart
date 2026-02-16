import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAttendanceRepository implements AttendanceRepository {
  Future<Either<Failure, Attendance>> Function(
      String, double, double, {String? branchName})? checkInStub;

  @override
  Future<Either<Failure, Attendance>> checkIn(
      String userId, double lat, double long,
      {String? branchName}) async {
    if (checkInStub != null) {
      return checkInStub!(userId, lat, long, branchName: branchName);
    }
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
      String attendanceId, double lat, double long) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(String userId) {
    throw UnimplementedError();
  }
}

void main() {
  late CheckIn useCase;
  late MockAttendanceRepository mockAttendanceRepository;

  setUp(() {
    mockAttendanceRepository = MockAttendanceRepository();
    useCase = CheckIn(mockAttendanceRepository);
  });

  const tUserId = 'testUser';
  const tLat = 12.34;
  const tLong = 56.78;
  const tBranchName = 'TestBranch';

  final tAttendance = Attendance(
    id: '1',
    userId: tUserId,
    checkInTime: DateTime(2023, 1, 1, 8, 0),
    latitude: tLat,
    longitude: tLong,
    branchName: tBranchName,
  );

  test(
    'should get attendance from the repository',
    () async {
      // arrange
      mockAttendanceRepository.checkInStub =
          (userId, lat, long, {branchName}) async {
        if (userId == tUserId &&
            lat == tLat &&
            long == tLong &&
            branchName == tBranchName) {
          return Right(tAttendance);
        }
        return const Left(ServerFailure('Invalid arguments'));
      };

      // act
      final result = await useCase(const CheckInParams(
        userId: tUserId,
        lat: tLat,
        long: tLong,
        branchName: tBranchName,
      ));

      // assert
      expect(result, Right(tAttendance));
    },
  );

  test(
    'should return a failure from the repository',
    () async {
      // arrange
      const tFailure = ServerFailure('Server Error');
      mockAttendanceRepository.checkInStub =
          (userId, lat, long, {branchName}) async {
        return const Left(tFailure);
      };

      // act
      final result = await useCase(const CheckInParams(
        userId: tUserId,
        lat: tLat,
        long: tLong,
        branchName: tBranchName,
      ));

      // assert
      expect(result, const Left(tFailure));
    },
  );
}
