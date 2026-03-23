import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class CacheDelegate implements UseCase<void, Delegate> {
  final AuthRepository repository;

  CacheDelegate(this.repository);

  @override
  Future<Either<Failure, void>> call(Delegate delegate) {
    return repository.cacheDelegate(delegate);
  }
}
