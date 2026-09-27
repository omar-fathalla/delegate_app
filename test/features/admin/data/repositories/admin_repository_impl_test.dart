import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/datasources/manage_marketing_remote_datasource.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAdminRemoteDataSource implements AdminRemoteDataSource {
  Future<List<BranchModel>> Function()? getBranchesStub;
  Future<BranchModel> Function(BranchModel)? addBranchStub;
  Future<BranchModel> Function(BranchModel)? updateBranchStub;
  Future<void> Function(String)? deleteBranchStub;

  int getBranchesCallCount = 0;
  int addBranchCallCount = 0;
  int updateBranchCallCount = 0;
  int deleteBranchCallCount = 0;
  BranchModel? lastAddedBranch;
  BranchModel? lastUpdatedBranch;
  String? lastDeletedId;

  @override
  Future<List<BranchModel>> getBranches() {
    getBranchesCallCount++;
    if (getBranchesStub != null) return getBranchesStub!();
    throw UnimplementedError();
  }

  @override
  Future<BranchModel> addBranch(BranchModel branch) {
    addBranchCallCount++;
    lastAddedBranch = branch;
    if (addBranchStub != null) return addBranchStub!(branch);
    throw UnimplementedError();
  }

  @override
  Future<BranchModel> updateBranch(BranchModel branch) {
    updateBranchCallCount++;
    lastUpdatedBranch = branch;
    if (updateBranchStub != null) return updateBranchStub!(branch);
    throw UnimplementedError();
  }

  @override
  Future<void> deleteBranch(String branchId) {
    deleteBranchCallCount++;
    lastDeletedId = branchId;
    if (deleteBranchStub != null) return deleteBranchStub!(branchId);
    throw UnimplementedError();
  }

  @override
  Future<AdminUserModel> createAdmin(AdminUserModel admin) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendActivationEmail({
    required String email,
    required String phoneNumber,
    required String temporaryPassword,
    required String displayName,
    String? role,
    String? companyName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> getCompaniesForOrg(
    String organizationUID,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<AdminUserModel>> getAdmins() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateAdminUser(AdminUserModel admin) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAdminUser(String adminId) {
    throw UnimplementedError();
  }

  @override
  Future<void> suspendAdminUser(String adminId, bool suspend) {
    throw UnimplementedError();
  }

  @override
  Future<List<DelegateModel>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<int> getTodayCheckedInCount(String organizationId, String companyId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> getOrganizations() {
    throw UnimplementedError();
  }

  @override
  Future<int> getTotalCompaniesCount(String organizationId) async {
    return 0;
  }
}

class MockManageMarketingRemoteDataSource
    implements ManageMarketingRemoteDataSource {
  @override
  Future<List<AdminUserModel>> getMarketingEmployees() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateMarketingEmployee(AdminUserModel employee) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteMarketingEmployee(String employeeId) {
    throw UnimplementedError();
  }

  @override
  Future<void> suspendMarketingEmployee(String employeeId, bool suspend) {
    throw UnimplementedError();
  }
}

void main() {
  late AdminRepositoryImpl repository;
  late MockAdminRemoteDataSource mockDataSource;
  late MockManageMarketingRemoteDataSource mockMarketingDataSource;

  setUp(() {
    mockDataSource = MockAdminRemoteDataSource();
    mockMarketingDataSource = MockManageMarketingRemoteDataSource();
    repository = AdminRepositoryImpl(
      remoteDataSource: mockDataSource,
      marketingDataSource: mockMarketingDataSource,
    );
  });

  const tBranch = BranchModel(
    id: 'b1',
    branchName: 'الفرع الرئيسي',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 200.0,
  );

  const tBranch2 = BranchModel(
    id: 'b2',
    branchName: 'فرع المعادي',
    latitude: 29.9602,
    longitude: 31.2569,
    geofenceRadius: 150.0,
  );

  group('getBranches', () {
    test('should return list of branches on success', () async {
      mockDataSource.getBranchesStub = () async => [tBranch, tBranch2];

      final result = await repository.getBranches();

      expect(mockDataSource.getBranchesCallCount, 1);
      result.fold(
        (failure) => fail('Should have returned Right'),
        (branches) => expect(branches, [tBranch, tBranch2]),
      );
    });

    test(
      'should return Left(Failure) when data source throws Failure',
      () async {
        const tFailure = ServerFailure('فشل في جلب بيانات الفروع.');
        mockDataSource.getBranchesStub = () => throw tFailure;

        final result = await repository.getBranches();

        expect(result, equals(const Left(tFailure)));
      },
    );

    test('should return Left(ServerFailure) on unexpected error', () async {
      mockDataSource.getBranchesStub = () => throw Exception('unexpected');

      final result = await repository.getBranches();

      expect(result, isA<Left<Failure, dynamic>>());
    });
  });

  group('addBranch', () {
    test('should return added branch on success', () async {
      mockDataSource.addBranchStub = (_) async => tBranch;

      final result = await repository.addBranch(tBranch);

      expect(mockDataSource.addBranchCallCount, 1);
      expect(result, equals(Right(tBranch)));
    });

    test(
      'should return Left(Failure) when data source throws Failure',
      () async {
        const tFailure = ServerFailure('فشل في إضافة الفرع.');
        mockDataSource.addBranchStub = (_) => throw tFailure;

        final result = await repository.addBranch(tBranch);

        expect(result, equals(const Left(tFailure)));
      },
    );
  });

  group('updateBranch', () {
    test('should return updated branch on success', () async {
      mockDataSource.updateBranchStub = (_) async => tBranch;

      final result = await repository.updateBranch(tBranch);

      expect(mockDataSource.updateBranchCallCount, 1);
      expect(result, equals(Right(tBranch)));
    });

    test(
      'should return Left(Failure) when data source throws Failure',
      () async {
        const tFailure = ServerFailure('فشل في تحديث بيانات الفرع.');
        mockDataSource.updateBranchStub = (_) => throw tFailure;

        final result = await repository.updateBranch(tBranch);

        expect(result, equals(const Left(tFailure)));
      },
    );
  });

  group('deleteBranch', () {
    test('should return Right(unit) on success', () async {
      mockDataSource.deleteBranchStub = (_) async {};

      final result = await repository.deleteBranch('b1');

      expect(mockDataSource.deleteBranchCallCount, 1);
      expect(mockDataSource.lastDeletedId, 'b1');
      expect(result, equals(const Right(unit)));
    });

    test(
      'should return Left(Failure) when data source throws Failure',
      () async {
        const tFailure = ServerFailure('فشل في حذف الفرع.');
        mockDataSource.deleteBranchStub = (_) => throw tFailure;

        final result = await repository.deleteBranch('b1');

        expect(result, equals(const Left(tFailure)));
      },
    );
  });
}
