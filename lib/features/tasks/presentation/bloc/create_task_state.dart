import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:equatable/equatable.dart';

abstract class CreateTaskState extends Equatable {
  final List<Delegate>? delegates;

  const CreateTaskState({this.delegates});

  @override
  List<Object?> get props => [delegates];
}

class CreateTaskInitial extends CreateTaskState {
  const CreateTaskInitial({super.delegates});
}

class CreateTaskLoading extends CreateTaskState {
  const CreateTaskLoading({super.delegates});
}

class LoadingDelegates extends CreateTaskState {}

class CreateTaskSuccess extends CreateTaskState {
  const CreateTaskSuccess({super.delegates});
}

class CreateTaskError extends CreateTaskState {
  final String message;

  const CreateTaskError({required this.message, super.delegates});

  @override
  List<Object?> get props => [message, delegates];
}
