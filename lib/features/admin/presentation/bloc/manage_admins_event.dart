part of 'manage_admins_bloc.dart';

abstract class ManageAdminsEvent extends Equatable {
  const ManageAdminsEvent();

  @override
  List<Object?> get props => [];
}

class LoadAdminsRequested extends ManageAdminsEvent {}

class DeleteAdminRequested extends ManageAdminsEvent {
  final String adminId;
  const DeleteAdminRequested({required this.adminId});

  @override
  List<Object?> get props => [adminId];
}

class SuspendAdminRequested extends ManageAdminsEvent {
  final String adminId;
  final bool suspend;
  const SuspendAdminRequested({required this.adminId, required this.suspend});

  @override
  List<Object?> get props => [adminId, suspend];
}

class UpdateAdminRequested extends ManageAdminsEvent {
  final AdminUser admin;
  const UpdateAdminRequested({required this.admin});

  @override
  List<Object?> get props => [admin];
}
