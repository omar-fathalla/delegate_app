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

  const LoadAdminTasksRequested({
    required this.organizationId,
    required this.companyId,
    this.status,
  });

  @override
  List<Object?> get props => [organizationId, companyId, status];
}

class LoadMoreAdminTasksRequested extends AdminTasksEvent {
  final String organizationId;
  final String companyId;

  const LoadMoreAdminTasksRequested({
    required this.organizationId,
    required this.companyId,
  });

  @override
  List<Object?> get props => [organizationId, companyId];
}

class StatusFilterChanged extends AdminTasksEvent {
  final String organizationId;
  final String companyId;
  final TaskStatus? status;

  const StatusFilterChanged({
    required this.organizationId,
    required this.companyId,
    this.status,
  });

  @override
  List<Object?> get props => [organizationId, companyId, status];
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
  final String taskId;

  const DeleteTaskRequested({required this.taskId});

  @override
  List<Object?> get props => [taskId];
}

class UpdateTaskRequested extends AdminTasksEvent {
  final String organizationId;
  final TaskEntity task;

  const UpdateTaskRequested({required this.organizationId, required this.task});

  @override
  List<Object> get props => [organizationId, task];
}
