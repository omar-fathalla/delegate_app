import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class AdminTasksState extends Equatable {
  final TaskStatus? statusFilter;
  const AdminTasksState({this.statusFilter});

  @override
  List<Object?> get props => [statusFilter];
}

class AdminTasksInitial extends AdminTasksState {
  const AdminTasksInitial() : super();
}

class AdminTasksLoading extends AdminTasksState {
  const AdminTasksLoading({super.statusFilter});
}

class AdminTasksLoaded extends AdminTasksState {
  final List<TaskEntity> tasks;
  final dynamic lastDoc;
  final bool hasReachedMax;
  final bool isLoadingMore;

  const AdminTasksLoaded({
    required this.tasks,
    super.statusFilter,
    this.lastDoc,
    this.hasReachedMax = false,
    this.isLoadingMore = false,
  });

  AdminTasksLoaded copyWith({
    List<TaskEntity>? tasks,
    TaskStatus? statusFilter,
    dynamic lastDoc,
    bool? hasReachedMax,
    bool? isLoadingMore,
  }) {
    return AdminTasksLoaded(
      tasks: tasks ?? this.tasks,
      statusFilter: statusFilter ?? this.statusFilter,
      lastDoc: lastDoc ?? this.lastDoc,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [
    tasks,
    statusFilter,
    lastDoc,
    hasReachedMax,
    isLoadingMore,
  ];
}

class AdminTasksError extends AdminTasksState {
  final String message;

  const AdminTasksError({required this.message, super.statusFilter});

  @override
  List<Object?> get props => [message, statusFilter];
}
