import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class CheckAutoLogin implements UseCase<Delegate?, NoParams> {
  final AuthRepository repository;

  CheckAutoLogin(this.repository);

  @override
  Future<Either<Failure, Delegate?>> call(NoParams params) async {
    return await repository.getCachedDelegate();
  }
}
