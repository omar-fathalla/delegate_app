import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class AdminRepositoryImpl implements AdminRepository {
  final AdminRemoteDataSource remoteDataSource;

  AdminRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, List<Branch>>> getBranches() async {
    try {
      final branches = await remoteDataSource.getBranches();
      return Right(branches);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Branch>> addBranch(Branch branch) async {
    try {
      final model = BranchModel(
        id: branch.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
      );
      final result = await remoteDataSource.addBranch(model);
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Branch>> updateBranch(Branch branch) async {
    try {
      final model = BranchModel(
        id: branch.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
      );
      final result = await remoteDataSource.updateBranch(model);
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteBranch(String branchId) async {
    try {
      await remoteDataSource.deleteBranch(branchId);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }
}
