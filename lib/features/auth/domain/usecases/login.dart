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
    // The login screen picks the account type, so each mode runs only its
    // own path. [LoginMode.auto] keeps the old delegate-then-staff chain for
    // callers that do not choose.
    if (params.mode == LoginMode.staff) return _loginStaff(params);
    final delegateResult = await repository.loginDelegate(
      phoneNumber: params.phoneNumber,
      nationalId: params.password,
    );

    // Only a credential miss falls through to staff. Pending, blocked,
    // rate-limited, and outages stay on the delegate path.
    return delegateResult.fold((failure) async {
      if (failure is! DelegateCredentialsFailure) return Left(failure);
      if (params.mode == LoginMode.delegate) return Left(failure);
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
          final blocking = _blockingFailure(isValid);
          if (blocking != null) return Left(blocking);
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
          final blocking = _blockingFailure(verifyResult);
          if (blocking != null) return Left(blocking);
          final isValid = verifyResult.fold((_) => false, (valid) => valid);
          if (isValid) matched.add(delegate);
        }
      }

      if (matched.isEmpty) {
        return Left(
          AuthFailure(
            params.mode == LoginMode.staff
                ? 'رقم الهاتف أو كلمة المرور غير صحيحة'
                : 'رقم الهاتف أو الرقم القومي غير صحيح',
            'invalid_credentials',
          ),
        );
      }

      return _finish(matched, params);
    });
  }

  /// Lockout and connectivity failures stop the staff chain so the screen
  /// can say so. Any other failure still counts as "no match".
  AuthFailure? _blockingFailure(Either<Failure, bool> result) {
    return result.fold((f) {
      if (f is AuthFailure && (f.code == 'rate_limited' || f.code == 'network')) {
        return f;
      }
      return null;
    }, (_) => null);
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

/// Account type chosen on the login screen.
enum LoginMode {
  /// Phone + national ID through `delegateLoginV2` only.
  delegate,

  /// Phone + password through the staff lookup and Firebase Auth only.
  staff,

  /// Delegate first, then staff on a credential miss (legacy behavior).
  auto,
}

class LoginParams extends Equatable {
  final String phoneNumber;

  /// National ID for delegates. Password for admin and other roles.
  final String password;
  final bool rememberMe;
  final LoginMode mode;

  const LoginParams({
    required this.phoneNumber,
    required this.password,
    this.rememberMe = false,
    this.mode = LoginMode.auto,
  });

  @override
  List<Object> get props => [phoneNumber, password, rememberMe, mode];
}
