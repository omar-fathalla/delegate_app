import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class AuthRepository {
  /// Delegate login: phone and national ID are both checked by
  /// `delegateLoginV2`. The returned profiles are the caller's own documents.
  Future<Either<Failure, List<Delegate>>> loginDelegate({
    required String phoneNumber,
    required String nationalId,
  });

  Future<Either<Failure, List<Delegate>>> getDelegatesByPhone(
    String phoneNumber,
  );
  Future<Either<Failure, void>> cacheDelegate(Delegate delegate);
  Future<Either<Failure, Delegate?>> getCachedDelegate();
  Future<Either<Failure, void>> cacheAllDelegates(List<Delegate> delegates);
  Future<Either<Failure, List<Delegate>>> getCachedAllDelegates();
  Future<Either<Failure, void>> clearCache();
  Future<Either<Failure, bool>> verifyAdminPassword(
    String email,
    String password,
  );
  Future<Either<Failure, bool>> verifyPhonePassword(
    String phoneNumber,
    String password,
  );
}
