import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class GetBranches implements UseCase<List<Branch>, NoParams> {
  final AdminRepository repository;

  GetBranches(this.repository);

  @override
  Future<Either<Failure, List<Branch>>> call(NoParams params) {
    return repository.getBranches();
  }
}
