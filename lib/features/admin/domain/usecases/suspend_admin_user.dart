import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class SuspendAdminUserParams {
  final String adminId;
  final bool suspend;
  const SuspendAdminUserParams({required this.adminId, required this.suspend});
}

class SuspendAdminUser implements UseCase<Unit, SuspendAdminUserParams> {
  final AdminRepository repository;

  SuspendAdminUser(this.repository);

  @override
  Future<Either<Failure, Unit>> call(SuspendAdminUserParams params) {
    return repository.suspendAdminUser(params.adminId, params.suspend);
  }
}
