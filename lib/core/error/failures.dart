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

/// Attendance refused because the delegate stands outside the branch's
/// geofence (TAS-397), from the app's own check or from the server
/// (`reason: outside_branch`). Still a [ServerFailure], so every existing
/// `is ServerFailure` / message path keeps working; the screen uses the type
/// to offer «الفرع مكانه غلط؟».
class GeofenceOutsideFailure extends ServerFailure {
  const GeofenceOutsideFailure(
    super.message, {
    this.distanceMeters,
    this.allowedMeters,
    this.branchId,
    this.branchName,
  });

  final double? distanceMeters;
  final double? allowedMeters;
  final String? branchId;
  final String? branchName;

  @override
  List<Object> get props => [
    message,
    distanceMeters ?? -1,
    allowedMeters ?? -1,
    branchId ?? '',
    branchName ?? '',
  ];
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
