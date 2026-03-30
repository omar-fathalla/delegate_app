import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class DeleteAdminUserParams {
  final String adminId;
  const DeleteAdminUserParams({required this.adminId});
}

class DeleteAdminUser implements UseCase<Unit, DeleteAdminUserParams> {
  final AdminRepository repository;

  DeleteAdminUser(this.repository);

  @override
  Future<Either<Failure, Unit>> call(DeleteAdminUserParams params) {
    return repository.deleteAdminUser(params.adminId);
  }
}
