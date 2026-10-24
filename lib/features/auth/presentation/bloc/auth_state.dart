part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthOrganizationSelectionRequired extends AuthState {
  final List<Delegate> delegates;
  final bool rememberMe;

  const AuthOrganizationSelectionRequired({
    required this.delegates,
    required this.rememberMe,
  });

  @override
  List<Object> get props => [delegates, rememberMe];
}

class AuthAuthenticated extends AuthState {
  final Delegate delegate;

  const AuthAuthenticated({required this.delegate});

  @override
  List<Object> get props => [delegate];
}

class AuthUnauthenticated extends AuthState {
  final String? message;

  const AuthUnauthenticated({this.message});

  @override
  List<Object> get props => message != null ? [message!] : [];
}

class AuthError extends AuthState {
  final String message;
  final String? code;

  const AuthError({required this.message, this.code});

  @override
  List<Object> get props => [message, code ?? ''];
}

class AuthDeviceMismatchState extends AuthState {
  final Delegate delegate;
  final String? boundDeviceModel;
  final String? currentDeviceModel;
  final String message;

  const AuthDeviceMismatchState({
    required this.delegate,
    this.boundDeviceModel,
    this.currentDeviceModel,
    required this.message,
  });

  @override
  List<Object> get props => [
    delegate,
    boundDeviceModel ?? '',
    currentDeviceModel ?? '',
    message,
  ];
}

