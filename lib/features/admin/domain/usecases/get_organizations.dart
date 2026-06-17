import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class GetOrganizations
    implements UseCase<List<Map<String, dynamic>>, NoParams> {
  final AdminRepository repository;

  GetOrganizations(this.repository);

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> call(NoParams params) {
    return repository.getOrganizations();
  }
}
