import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class Login implements UseCase<List<Delegate>, LoginParams> {
  final AuthRepository repository;

  Login(this.repository);

  @override
  Future<Either<Failure, List<Delegate>>> call(LoginParams params) async {
    final delegateResult = await repository.loginDelegate(
      phoneNumber: params.phoneNumber,
      nationalId: params.password,
    );

    // Only a credential miss falls through to staff. Pending, blocked,
    // rate-limited, and outages stay on the delegate path.
    return delegateResult.fold((failure) async {
      if (failure is! DelegateCredentialsFailure) return Left(failure);
      return _loginStaff(params);
    }, (delegates) => _finish(delegates, params));
  }

  Future<Either<Failure, List<Delegate>>> _loginStaff(LoginParams params) async {
    // Staff phone lookup reads only `users`. Delegate documents are not
    // consulted, and only a Firebase Auth email marker can continue.
    final result = await repository.getDelegatesByPhone(params.phoneNumber);

    return result.fold((failure) => Left(failure), (delegates) async {
      final matched = <Delegate>[];

      for (final delegate in delegates) {
        if (delegate.nationalityID.startsWith('__phone_auth__:')) {
          final phone = delegate.nationalityID.replaceFirst(
            '__phone_auth__:',
            '',
          );
          final isValid = await repository.verifyPhonePassword(
            phone,
            params.password,
          );
          final valid = isValid.fold((_) => false, (v) => v);
          if (valid) matched.add(delegate);
        } else if (delegate.nationalityID.startsWith('__firebase_auth__:')) {
          final email = delegate.nationalityID.replaceFirst(
            '__firebase_auth__:',
            '',
          );
          final verifyResult = await repository.verifyAdminPassword(
            email,
            params.password,
          );
          final isValid = verifyResult.fold((_) => false, (valid) => valid);
          if (isValid) matched.add(delegate);
        }
      }

      if (matched.isEmpty) {
        return const Left(
          AuthFailure(
            'رقم الهاتف أو الرقم القومي غير صحيح',
            'invalid_credentials',
          ),
        );
      }

      return _finish(matched, params);
    });
  }

  Future<Either<Failure, List<Delegate>>> _finish(
    List<Delegate> matched,
    LoginParams params,
  ) async {
    if (matched.length == 1 && params.rememberMe) {
      await repository.cacheDelegate(matched.first);
    }
    return Right(matched);
  }
}

class LoginParams extends Equatable {
  final String phoneNumber;

  /// National ID for delegates. Password for admin and other roles.
  final String password;
  final bool rememberMe;

  const LoginParams({
    required this.phoneNumber,
    required this.password,
    this.rememberMe = false,
  });

  @override
  List<Object> get props => [phoneNumber, password, rememberMe];
}
