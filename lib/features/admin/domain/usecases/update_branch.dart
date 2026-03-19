import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class UpdateBranchParams {
  final Branch branch;
  const UpdateBranchParams({required this.branch});
}

class UpdateBranch implements UseCase<Branch, UpdateBranchParams> {
  final AdminRepository repository;

  UpdateBranch(this.repository);

  @override
  Future<Either<Failure, Branch>> call(UpdateBranchParams params) {
    return repository.updateBranch(params.branch);
  }
}
