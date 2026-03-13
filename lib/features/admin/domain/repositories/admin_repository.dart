import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';

abstract class AdminRepository {
  Future<Either<Failure, List<Branch>>> getBranches();
  Future<Either<Failure, Branch>> addBranch(Branch branch);
  Future<Either<Failure, Branch>> updateBranch(Branch branch);
  Future<Either<Failure, Unit>> deleteBranch(String branchId);
}
