import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class DelegateTasksEvent extends Equatable {
  const DelegateTasksEvent();

  @override
  List<Object?> get props => [];
}

class LoadDelegateTasksRequested extends DelegateTasksEvent {
  final String organizationId;
  final String delegateId;
  final String companyId;
  final String delegateRoleName;
  final TaskStatus? status;

  const LoadDelegateTasksRequested({
    required this.organizationId,
    required this.delegateId,
    required this.companyId,
    required this.delegateRoleName,
    this.status,
  });

  @override
  List<Object?> get props => [organizationId, delegateId, companyId, delegateRoleName, status];
}

class LoadMoreDelegateTasksRequested extends DelegateTasksEvent {
  final String organizationId;
  final String delegateId;
  final String companyId;
  final String delegateRoleName;

  const LoadMoreDelegateTasksRequested({
    required this.organizationId,
    required this.delegateId,
    required this.companyId,
    required this.delegateRoleName,
  });

  @override
  List<Object?> get props => [organizationId, delegateId, companyId, delegateRoleName];
}

class StatusFilterChangedDelegate extends DelegateTasksEvent {
  final String organizationId;
  final String delegateId;
  final String companyId;
  final String delegateRoleName;
  final TaskStatus? status;

  const StatusFilterChangedDelegate({
    required this.organizationId,
    required this.delegateId,
    required this.companyId,
    required this.delegateRoleName,
    this.status,
  });

  @override
  List<Object?> get props => [organizationId, delegateId, companyId, delegateRoleName, status];
}

class UpdateTaskStatusRequested extends DelegateTasksEvent {
  final String organizationId;
  final String taskId;
  final TaskStatus newStatus;
  final String? notes;

  const UpdateTaskStatusRequested({
    required this.organizationId,
    required this.taskId,
    required this.newStatus,
    this.notes,
  });

  @override
  List<Object?> get props => [organizationId, taskId, newStatus, notes];
}

class UpdateTaskRequestedDelegate extends DelegateTasksEvent {
  final String organizationId;
  final TaskEntity task;

  const UpdateTaskRequestedDelegate({
    required this.organizationId,
    required this.task,
  });

  @override
  List<Object?> get props => [organizationId, task];
}
