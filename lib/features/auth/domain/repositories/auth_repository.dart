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

  /// TAS-272: refresh a signed-in delegate's chains (active / pending only).
  Future<Either<Failure, List<Delegate>>> refreshDelegateProfiles(
    String phoneNumber,
  );
  Future<Either<Failure, void>> cacheDelegate(Delegate delegate);
  Future<Either<Failure, Delegate?>> getCachedDelegate();
  Future<Either<Failure, void>> cacheAllDelegates(List<Delegate> delegates);
  Future<Either<Failure, List<Delegate>>> getCachedAllDelegates();
  Future<Either<Failure, void>> clearCache();

  /// Signs out of Firebase Auth, drops the remember-me cache and selected
  /// organization list, and best-effort clears the push registration for
  /// [userId]. Always clears local state, even when sign-out or the network
  /// fails.
  Future<Either<Failure, void>> logout({String? userId});
  Future<Either<Failure, bool>> verifyAdminPassword(
    String email,
    String password,
  );
  Future<Either<Failure, bool>> verifyPhonePassword(
    String phoneNumber,
    String password,
  );
}
