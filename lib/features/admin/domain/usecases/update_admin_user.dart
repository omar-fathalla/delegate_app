import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class UpdateAdminUserParams {
  final AdminUser admin;
  const UpdateAdminUserParams({required this.admin});
}

class UpdateAdminUser implements UseCase<Unit, UpdateAdminUserParams> {
  final AdminRepository repository;

  UpdateAdminUser(this.repository);

  @override
  Future<Either<Failure, Unit>> call(UpdateAdminUserParams params) {
    return repository.updateAdminUser(params.admin);
  }
}
