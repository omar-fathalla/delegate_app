import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class AuthRepository {
  Future<Either<Failure, List<Delegate>>> getDelegatesByPhone(
    String phoneNumber,
  );
  Future<Either<Failure, void>> cacheDelegate(Delegate delegate);
  Future<Either<Failure, Delegate?>> getCachedDelegate();
  Future<Either<Failure, void>> cacheAllDelegates(List<Delegate> delegates);
  Future<Either<Failure, List<Delegate>>> getCachedAllDelegates();
  Future<Either<Failure, void>> clearCache();
}
