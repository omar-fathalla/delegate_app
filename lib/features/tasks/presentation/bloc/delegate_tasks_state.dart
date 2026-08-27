import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class DelegateTasksState extends Equatable {
  final TaskStatus? statusFilter;
  const DelegateTasksState({this.statusFilter});

  @override
  List<Object?> get props => [statusFilter];
}

class DelegateTasksInitial extends DelegateTasksState {
  const DelegateTasksInitial() : super();
}

class DelegateTasksLoading extends DelegateTasksState {
  const DelegateTasksLoading({super.statusFilter});
}

class DelegateTasksLoaded extends DelegateTasksState {
  final List<TaskEntity> tasks;
  final Object? lastDoc;
  final bool hasReachedMax;
  final bool isLoadingMore;

  const DelegateTasksLoaded({
    required this.tasks,
    this.lastDoc,
    this.hasReachedMax = false,
    this.isLoadingMore = false,
    super.statusFilter,
  });

  DelegateTasksLoaded copyWith({
    List<TaskEntity>? tasks,
    Object? lastDoc,
    bool? hasReachedMax,
    bool? isLoadingMore,
    TaskStatus? statusFilter,
  }) {
    return DelegateTasksLoaded(
      tasks: tasks ?? this.tasks,
      lastDoc: lastDoc ?? this.lastDoc,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }

  @override
  List<Object?> get props => [
    tasks,
    lastDoc,
    hasReachedMax,
    isLoadingMore,
    statusFilter,
  ];
}

class DelegateTasksError extends DelegateTasksState {
  final String message;

  const DelegateTasksError({required this.message, super.statusFilter});

  @override
  List<Object?> get props => [message, statusFilter];
}

class TaskStatusUpdateSuccess extends DelegateTasksState {
  final TaskStatus? newStatus;
  const TaskStatusUpdateSuccess({this.newStatus, super.statusFilter});

  @override
  List<Object?> get props => [newStatus, statusFilter];
}
