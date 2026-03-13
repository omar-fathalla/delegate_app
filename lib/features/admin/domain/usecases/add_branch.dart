import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class AddBranchParams {
  final Branch branch;
  const AddBranchParams({required this.branch});
}

class AddBranch implements UseCase<Branch, AddBranchParams> {
  final AdminRepository repository;

  AddBranch(this.repository);

  @override
  Future<Either<Failure, Branch>> call(AddBranchParams params) {
    return repository.addBranch(params.branch);
  }
}
