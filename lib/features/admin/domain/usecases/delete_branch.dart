import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class DeleteBranchParams {
  final String branchId;
  const DeleteBranchParams({required this.branchId});
}

class DeleteBranch implements UseCase<Unit, DeleteBranchParams> {
  final AdminRepository repository;

  DeleteBranch(this.repository);

  @override
  Future<Either<Failure, Unit>> call(DeleteBranchParams params) {
    return repository.deleteBranch(params.branchId);
  }
}
