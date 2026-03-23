import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class CacheAllDelegates implements UseCase<void, List<Delegate>> {
  final AuthRepository repository;

  CacheAllDelegates(this.repository);

  @override
  Future<Either<Failure, void>> call(List<Delegate> delegates) {
    return repository.cacheAllDelegates(delegates);
  }
}
