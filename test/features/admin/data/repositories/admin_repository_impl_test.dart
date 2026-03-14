import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAdminRemoteDataSource implements AdminRemoteDataSource {
  Object? throwOnGetBranches;
  Object? throwOnAddBranch;
  Object? throwOnUpdateBranch;
  Object? throwOnDeleteBranch;

  @override
  Future<List<BranchModel>> getBranches() async {
    if (throwOnGetBranches != null) throw throwOnGetBranches!;
    return [];
  }

  @override
  Future<BranchModel> addBranch(BranchModel branch) async {
    if (throwOnAddBranch != null) throw throwOnAddBranch!;
    return branch;
  }

  @override
  Future<BranchModel> updateBranch(BranchModel branch) async {
    if (throwOnUpdateBranch != null) throw throwOnUpdateBranch!;
    return branch;
  }

  @override
  Future<void> deleteBranch(String branchId) async {
    if (throwOnDeleteBranch != null) throw throwOnDeleteBranch!;
  }
}

void main() {
  late AdminRepositoryImpl repository;
  late MockAdminRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockAdminRemoteDataSource();
    repository = AdminRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  final tBranch = BranchModel(
    id: '1',
    branchName: 'test',
    latitude: 1.0,
    longitude: 1.0,
    geofenceRadius: 100,
  );

  group('getBranches', () {
    test('should return Failure when Failure is thrown', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemoteDataSource.throwOnGetBranches = tFailure;
      final result = await repository.getBranches();
      expect(result, equals(const Left(tFailure)));
    });

    test('should return ServerFailure when unexpected Exception is thrown', () async {
      mockRemoteDataSource.throwOnGetBranches = Exception('Unexpected Error');
      final result = await repository.getBranches();
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });
  });

  group('addBranch', () {
    test('should return Failure when Failure is thrown', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemoteDataSource.throwOnAddBranch = tFailure;
      final result = await repository.addBranch(tBranch);
      expect(result, equals(const Left(tFailure)));
    });

    test('should return ServerFailure when unexpected Exception is thrown', () async {
      mockRemoteDataSource.throwOnAddBranch = Exception('Unexpected Error');
      final result = await repository.addBranch(tBranch);
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });
  });

  group('updateBranch', () {
    test('should return Failure when Failure is thrown', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemoteDataSource.throwOnUpdateBranch = tFailure;
      final result = await repository.updateBranch(tBranch);
      expect(result, equals(const Left(tFailure)));
    });

    test('should return ServerFailure when unexpected Exception is thrown', () async {
      mockRemoteDataSource.throwOnUpdateBranch = Exception('Unexpected Error');
      final result = await repository.updateBranch(tBranch);
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });
  });

  group('deleteBranch', () {
    test('should return Failure when Failure is thrown', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemoteDataSource.throwOnDeleteBranch = tFailure;
      final result = await repository.deleteBranch('1');
      expect(result, equals(const Left(tFailure)));
    });

    test('should return ServerFailure when unexpected Exception is thrown', () async {
      mockRemoteDataSource.throwOnDeleteBranch = Exception('Unexpected Error');
      final result = await repository.deleteBranch('1');
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });
  });
}
