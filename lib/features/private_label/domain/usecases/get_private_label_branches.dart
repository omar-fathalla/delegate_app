import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

/// Params: organization UID. Returns sorted branch names.
class GetPrivateLabelBranches implements UseCase<List<String>, String> {
  final PrivateLabelRepository repository;

  GetPrivateLabelBranches(this.repository);

  @override
  Future<Either<Failure, List<String>>> call(String organizationUID) {
    return repository.getBranches(organizationUID);
  }
}
