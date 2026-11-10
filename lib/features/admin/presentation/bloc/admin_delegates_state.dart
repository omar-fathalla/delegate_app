import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:equatable/equatable.dart';

abstract class AdminDelegatesState extends Equatable {
  const AdminDelegatesState();

  @override
  List<Object?> get props => [];
}

class AdminDelegatesInitial extends AdminDelegatesState {}

class AdminDelegatesLoading extends AdminDelegatesState {}

class AdminDelegatesLoaded extends AdminDelegatesState {
  final List<Delegate> delegates;
  final String? warning;

  const AdminDelegatesLoaded({required this.delegates, this.warning});

  @override
  List<Object?> get props => [delegates, warning];
}

class AdminDelegatesError extends AdminDelegatesState {
  final String message;

  const AdminDelegatesError({required this.message});

  @override
  List<Object?> get props => [message];
}
