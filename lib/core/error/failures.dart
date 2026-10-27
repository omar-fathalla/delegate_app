import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure([this.message = '']);

  final String message;

  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure([super.message]);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message]);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = '', this.code]);

  /// Stable code the login screens translate. Null keeps [message] as-is.
  final String? code;

  @override
  List<Object> get props => <Object>[message, code ?? ''];
}

/// Phone and national ID did not match a delegate. Staff login may continue.
class DelegateCredentialsFailure extends AuthFailure {
  const DelegateCredentialsFailure([String message = ''])
    : super(message, 'invalid_credentials');
}

/// The delegate exists but is pending, blocked, suspended, or rejected.
class DelegateAccountInactiveFailure extends AuthFailure {
  const DelegateAccountInactiveFailure([String message = ''])
    : super(message, 'account_inactive');
}

class DelegateRateLimitFailure extends AuthFailure {
  const DelegateRateLimitFailure([String message = ''])
    : super(message, 'rate_limited');
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message]);
}
