part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

class LoginRequested extends AuthEvent {
  final String mobile;
  final String motherName;

  const LoginRequested({required this.mobile, required this.motherName});

  @override
  List<Object> get props => [mobile, motherName];
}

class LogoutRequested extends AuthEvent {}
