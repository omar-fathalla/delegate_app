import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAttendanceRepository implements AttendanceRepository {
  Future<Either<Failure, Attendance>> Function(
    String,
    double,
    double, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
  })?
  checkInStub;

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
    if (checkInStub != null) {
      return checkInStub!(
        userId,
        lat,
        long,
        companyId: companyId,
        organizationId: organizationId,
        deviceInfo: deviceInfo,
        branchName: branchName,
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long, {
    required String userId,
    required String organizationId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(String userId, String organizationId) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Attendance?>> findActiveAttendance(String userId, String organizationId) {
    throw UnimplementedError();
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
  late CheckIn useCase;
  late MockAttendanceRepository mockAttendanceRepository;

  setUp(() {
    mockAttendanceRepository = MockAttendanceRepository();
    useCase = CheckIn(mockAttendanceRepository);
  });

  const tUserId = 'testUser';
  const tCompanyId = 'testCompany';
  const tOrganizationId = 'testOrg';
  const tDeviceInfo = 'testDevice';
  const tLat = 12.34;
  const tLong = 56.78;
  const tBranchName = 'TestBranch';

  final tAttendance = Attendance(
    id: '1',
    userId: tUserId,
    organizationId: tOrganizationId,
    checkInTime: DateTime(2023, 1, 1, 8, 0),
    latitude: tLat,
    longitude: tLong,
    branchName: tBranchName,
  );

  test('should get attendance from the repository', () async {
    // arrange
    mockAttendanceRepository.checkInStub =
        (
          userId,
          lat,
          long, {
          required companyId,
          required organizationId,
          required deviceInfo,
          branchName,
        }) async {
          if (userId == tUserId &&
              lat == tLat &&
              long == tLong &&
              companyId == tCompanyId &&
              organizationId == tOrganizationId &&
              deviceInfo == tDeviceInfo &&
              branchName == tBranchName) {
            return Right(tAttendance);
          }
          return const Left(ServerFailure('Invalid arguments'));
        };

    // act
    final result = await useCase(
      const CheckInParams(
        userId: tUserId,
        lat: tLat,
        long: tLong,
        companyId: tCompanyId,
        organizationId: tOrganizationId,
        deviceInfo: tDeviceInfo,
        branchName: tBranchName,
      ),
    );

    // assert
    expect(result, Right(tAttendance));
  });

  test('should return a failure from the repository', () async {
    // arrange
    const tFailure = ServerFailure('Server Error');
    mockAttendanceRepository.checkInStub =
        (
          userId,
          lat,
          long, {
          required companyId,
          required organizationId,
          required deviceInfo,
          branchName,
        }) async {
          return const Left(tFailure);
        };

    // act
    final result = await useCase(
      const CheckInParams(
        userId: tUserId,
        lat: tLat,
        long: tLong,
        companyId: tCompanyId,
        organizationId: tOrganizationId,
        deviceInfo: tDeviceInfo,
        branchName: tBranchName,
      ),
    );

    // assert
    expect(result, const Left(tFailure));
  });
}
