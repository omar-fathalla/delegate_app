part of 'manage_admins_bloc.dart';

abstract class ManageAdminsState extends Equatable {
  const ManageAdminsState();

  @override
  List<Object?> get props => [];
}

class ManageAdminsInitial extends ManageAdminsState {}

class ManageAdminsLoading extends ManageAdminsState {}

class ManageAdminsLoaded extends ManageAdminsState {
  final List<AdminUser> admins;
  const ManageAdminsLoaded({required this.admins});

  @override
  List<Object?> get props => [admins];
}

class ManageAdminsError extends ManageAdminsState {
  final String message;
  const ManageAdminsError({required this.message});

  @override
  List<Object?> get props => [message];
}
