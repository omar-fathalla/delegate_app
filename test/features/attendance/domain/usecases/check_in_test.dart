import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance_pagination_result.dart';
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
    String? branchId,
    String? branchOrganizationUID,
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
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
    String? branchId,
    String? branchOrganizationUID,
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
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
        delegateName: delegateName,
        phoneNumber: phoneNumber,
        companyName: companyName,
        personalPhotoURL: personalPhotoURL,
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
  Future<Either<Failure, List<Attendance>>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, AttendancePaginationResult>> getHistoryPaginated(
    String userId,
    String organizationId, {
    int limit = 20,
    String? nationalityID,
    String? phoneNumber,
    dynamic lastDoc,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Attendance?>> findActiveAttendance(
    String userId,
    String organizationId,
  ) {
    throw UnimplementedError();
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
          branchId,
          branchOrganizationUID,
          delegateName,
          phoneNumber,
          companyName,
          personalPhotoURL,
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
          branchId,
          branchOrganizationUID,
          delegateName,
          phoneNumber,
          companyName,
          personalPhotoURL,
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
