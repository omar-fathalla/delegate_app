import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class GetCompaniesForOrg implements UseCase<List<Map<String, dynamic>>, String> {
  final AdminRepository repository;

  GetCompaniesForOrg(this.repository);

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> call(String organizationUID) {
    return repository.getCompaniesForOrg(organizationUID);
  }
}
