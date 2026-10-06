import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class AdminTasksEvent extends Equatable {
  const AdminTasksEvent();

  @override
  List<Object?> get props => [];
}

class LoadAdminTasksRequested extends AdminTasksEvent {
  final String organizationId;
  final String companyId;
  final TaskStatus? status;
  final String? adminId;
  final String? adminRoleName;

  const LoadAdminTasksRequested({
    required this.organizationId,
    required this.companyId,
    this.status,
    this.adminId,
    this.adminRoleName,
  });

  @override
  List<Object?> get props => [organizationId, companyId, status, adminId, adminRoleName];
}

class LoadMoreAdminTasksRequested extends AdminTasksEvent {
  final String organizationId;
  final String companyId;
  final String? adminId;
  final String? adminRoleName;

  const LoadMoreAdminTasksRequested({
    required this.organizationId,
    required this.companyId,
    this.adminId,
    this.adminRoleName,
  });

  @override
  List<Object?> get props => [organizationId, companyId, adminId, adminRoleName];
}

class StatusFilterChanged extends AdminTasksEvent {
  final String organizationId;
  final String companyId;
  final TaskStatus? status;
  final String? adminId;
  final String? adminRoleName;

  const StatusFilterChanged({
    required this.organizationId,
    required this.companyId,
    this.status,
    this.adminId,
    this.adminRoleName,
  });

  @override
  List<Object?> get props => [organizationId, companyId, status, adminId, adminRoleName];
}

class AdminTaskStatusUpdateRequested extends AdminTasksEvent {
  final String organizationId;
  final String taskId;
  final TaskStatus newStatus;
  final String? notes;

  const AdminTaskStatusUpdateRequested({
    required this.organizationId,
    required this.taskId,
    required this.newStatus,
    this.notes,
  });

  @override
  List<Object?> get props => [organizationId, taskId, newStatus, notes];
}

class DeleteTaskRequested extends AdminTasksEvent {
  final String organizationId;
  final String taskId;

  const DeleteTaskRequested({
    required this.organizationId,
    required this.taskId,
  });

  @override
  List<Object?> get props => [organizationId, taskId];
}

class UpdateTaskRequested extends AdminTasksEvent {
  final String organizationId;
  final TaskEntity task;

  const UpdateTaskRequested({required this.organizationId, required this.task});

  @override
  List<Object> get props => [organizationId, task];
}
