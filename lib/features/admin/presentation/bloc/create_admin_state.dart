part of 'create_admin_bloc.dart';

abstract class CreateAdminState extends Equatable {
  const CreateAdminState();

  @override
  List<Object?> get props => [];
}

class CreateAdminInitial extends CreateAdminState {}

class CreateAdminLoading extends CreateAdminState {}

class CreateAdminSuccess extends CreateAdminState {
  final AdminUser adminUser;

  const CreateAdminSuccess({required this.adminUser});

  @override
  List<Object?> get props => [adminUser];
}

class CreateAdminError extends CreateAdminState {
  final String message;

  const CreateAdminError({required this.message});

  @override
  List<Object?> get props => [message];
}
