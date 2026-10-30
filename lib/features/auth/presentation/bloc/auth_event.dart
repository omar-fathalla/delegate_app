part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

class LoginRequested extends AuthEvent {
  final String phoneNumber;
  final String password;
  final bool rememberMe;
  final LoginMode mode;

  const LoginRequested({
    required this.phoneNumber,
    required this.password,
    this.rememberMe = false,
    this.mode = LoginMode.auto,
  });

  @override
  List<Object> get props => [phoneNumber, password, rememberMe, mode];
}

class CheckAutoLoginRequested extends AuthEvent {}

class AnonymousSessionDetected extends AuthEvent {
  const AnonymousSessionDetected();
}

class LogoutRequested extends AuthEvent {
  final String? userId;

  const LogoutRequested({this.userId});

  @override
  List<Object> get props => [userId ?? ''];
}

class PhoneOtpVerified extends AuthEvent {
  const PhoneOtpVerified();
}

class PhoneOtpCancelled extends AuthEvent {
  const PhoneOtpCancelled();
}

class OrganizationSelected extends AuthEvent {
  final Delegate delegate;
  final bool rememberMe;

  const OrganizationSelected({
    required this.delegate,
    required this.rememberMe,
  });

  @override
  List<Object> get props => [delegate, rememberMe];
}
