import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class GetMarketingEmployees implements UseCase<List<AdminUser>, NoParams> {
  final AdminRepository repository;

  GetMarketingEmployees(this.repository);

  @override
  Future<Either<Failure, List<AdminUser>>> call(NoParams params) {
    return repository.getMarketingEmployees();
  }
}
