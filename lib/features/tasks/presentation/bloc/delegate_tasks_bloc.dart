import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_delegate_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_state.dart';

class DelegateTasksBloc extends Bloc<DelegateTasksEvent, DelegateTasksState> {
  final GetDelegateTasks getDelegateTasks;
  final UpdateTaskStatus updateTaskStatus;
  final UpdateTask updateTask;

  DelegateTasksBloc({
    required this.getDelegateTasks,
    required this.updateTaskStatus,
    required this.updateTask,
  }) : super(DelegateTasksInitial()) {
    on<LoadDelegateTasksRequested>(_onLoadTasks);
    on<LoadMoreDelegateTasksRequested>(_onLoadMoreTasks);
    on<StatusFilterChangedDelegate>(_onStatusFilterChanged);
    on<UpdateTaskStatusRequested>(_onUpdateStatus);
    on<UpdateTaskRequestedDelegate>(_onUpdateTask);
  }

  Future<void> _onLoadTasks(
    LoadDelegateTasksRequested event,
    Emitter<DelegateTasksState> emit,
  ) async {
    emit(DelegateTasksLoading(statusFilter: event.status));
    final result = await getDelegateTasks(
      event.organizationId,
      event.delegateId,
      event.companyId,
      status: event.status,
      limit: 20,
    );
    result.fold(
      (failure) => emit(
        DelegateTasksError(
          message: failure.message,
          statusFilter: event.status,
        ),
      ),
      (tasks) => emit(
        DelegateTasksLoaded(
          tasks: tasks,
          lastDoc: tasks.isNotEmpty
              ? tasks.last.uid
              : null, // Store UID as ref or the object itself if supported
          hasReachedMax: tasks.length < 20,
          statusFilter: event.status,
        ),
      ),
    );
  }

  Future<void> _onLoadMoreTasks(
    LoadMoreDelegateTasksRequested event,
    Emitter<DelegateTasksState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DelegateTasksLoaded ||
        currentState.hasReachedMax ||
        currentState.isLoadingMore) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));

    final result = await getDelegateTasks(
      event.organizationId,
      event.delegateId,
      event.companyId,
      status: currentState.statusFilter,
      lastDoc: currentState.lastDoc,
      limit: 20,
    );

    result.fold(
      (failure) => emit(
        DelegateTasksError(
          message: failure.message,
          statusFilter: currentState.statusFilter,
        ),
      ),
      (newTasks) => emit(
        currentState.copyWith(
          tasks: List.of(currentState.tasks)..addAll(newTasks),
          lastDoc: newTasks.isNotEmpty
              ? newTasks.last.uid
              : currentState.lastDoc,
          hasReachedMax: newTasks.length < 20,
          isLoadingMore: false,
        ),
      ),
    );
  }

  Future<void> _onStatusFilterChanged(
    StatusFilterChangedDelegate event,
    Emitter<DelegateTasksState> emit,
  ) async {
    add(
      LoadDelegateTasksRequested(
        organizationId: event.organizationId,
        delegateId: event.delegateId,
        companyId: event.companyId,
        status: event.status,
      ),
    );
  }

  Future<void> _onUpdateStatus(
    UpdateTaskStatusRequested event,
    Emitter<DelegateTasksState> emit,
  ) async {
    // We don't necessarily want to emit loading here if we want a smooth transition,
    // but for now let's keep it simple.
    final result = await updateTaskStatus(
      event.organizationId,
      event.taskId,
      event.newStatus,
      notes: event.notes,
    );

    result.fold(
      (failure) => emit(
        DelegateTasksError(
          message: failure.message,
          statusFilter: (state is DelegateTasksLoaded)
              ? (state as DelegateTasksLoaded).statusFilter
              : (state is DelegateTasksLoading)
              ? (state as DelegateTasksLoading).statusFilter
              : null,
        ),
      ),
      (_) {
        // Emit success and potentially reload
        emit(TaskStatusUpdateSuccess());
        // Auto-reload to show the updated status
        if (state is DelegateTasksLoaded || state is TaskStatusUpdateSuccess) {
          // We might need to store the last event params or keep them in the state
          // For now, let's assume the UI will trigger a reload on success if it needs to,
          // or we could have kept the original Loaded state.
        }
      },
    );
  }

  Future<void> _onUpdateTask(
    UpdateTaskRequestedDelegate event,
    Emitter<DelegateTasksState> emit,
  ) async {
    final result = await updateTask(event.organizationId, event.task);

    result.fold(
      (failure) => emit(
        DelegateTasksError(
          message: failure.message,
          statusFilter: (state is DelegateTasksLoaded)
              ? (state as DelegateTasksLoaded).statusFilter
              : (state is DelegateTasksLoading)
              ? (state as DelegateTasksLoading).statusFilter
              : null,
        ),
      ),
      (_) {
        if (state is DelegateTasksLoaded) {
          final currentState = state as DelegateTasksLoaded;
          final updatedTasks = currentState.tasks.map((t) {
            return t.uid == event.task.uid ? event.task : t;
          }).toList();
          emit(currentState.copyWith(tasks: updatedTasks));
        }
      },
    );
  }
}
