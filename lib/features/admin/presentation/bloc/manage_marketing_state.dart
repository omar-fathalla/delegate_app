part of 'manage_marketing_bloc.dart';

abstract class ManageMarketingState extends Equatable {
  const ManageMarketingState();

  @override
  List<Object?> get props => [];
}

class ManageMarketingInitial extends ManageMarketingState {}

class ManageMarketingLoading extends ManageMarketingState {}

class ManageMarketingLoaded extends ManageMarketingState {
  final List<AdminUser> employees;
  const ManageMarketingLoaded({required this.employees});

  @override
  List<Object?> get props => [employees];
}

class ManageMarketingError extends ManageMarketingState {
  final String message;
  const ManageMarketingError({required this.message});

  @override
  List<Object?> get props => [message];
}
