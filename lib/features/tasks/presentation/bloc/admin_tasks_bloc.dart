import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_admin_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_state.dart';

class AdminTasksBloc extends Bloc<AdminTasksEvent, AdminTasksState> {
  final GetAdminTasks getAdminTasks;
  final UpdateTaskStatus updateTaskStatus;
  final UpdateTask updateTask;

  AdminTasksBloc({
    required this.getAdminTasks,
    required this.updateTaskStatus,
    required this.updateTask,
  }) : super(AdminTasksInitial()) {
    on<LoadAdminTasksRequested>(_onLoadTasks);
    on<LoadMoreAdminTasksRequested>(_onLoadMoreTasks);
    on<StatusFilterChanged>(_onStatusFilterChanged);
    on<AdminTaskStatusUpdateRequested>(_onUpdateStatus);
    on<UpdateTaskRequested>(_onUpdateTask);
  }

  static const int _pageSize = 20;

  Future<void> _onLoadTasks(
    LoadAdminTasksRequested event,
    Emitter<AdminTasksState> emit,
  ) async {
    emit(AdminTasksLoading(statusFilter: event.status));
    final result = await getAdminTasks(
      event.organizationId,
      event.companyId,
      status: event.status,
      limit: _pageSize,
      adminId: event.adminId,
      adminRoleName: event.adminRoleName,
    );
    result.fold(
      (failure) => emit(
        AdminTasksError(message: failure.message, statusFilter: event.status),
      ),
      (tasks) => emit(
        AdminTasksLoaded(
          tasks: tasks,
          statusFilter: event.status,
          lastDoc: tasks.isNotEmpty ? tasks.last.createdAt : null,
          hasReachedMax: tasks.length < _pageSize,
        ),
      ),
    );
  }

  Future<void> _onLoadMoreTasks(
    LoadMoreAdminTasksRequested event,
    Emitter<AdminTasksState> emit,
  ) async {
    final currentState = state;
    if (currentState is! AdminTasksLoaded ||
        currentState.hasReachedMax ||
        currentState.isLoadingMore) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));

    final result = await getAdminTasks(
      event.organizationId,
      event.companyId,
      status: currentState.statusFilter,
      limit: _pageSize,
      lastDoc: currentState.lastDoc,
      adminId: event.adminId,
      adminRoleName: event.adminRoleName,
    );

    result.fold(
      (failure) => emit(
        AdminTasksError(
          message: failure.message,
          statusFilter: currentState.statusFilter,
        ),
      ), // Or handle silently
      (newTasks) {
        final allTasks = List<TaskEntity>.from(currentState.tasks)
          ..addAll(newTasks);
        emit(
          currentState.copyWith(
            tasks: allTasks,
            lastDoc: newTasks.isNotEmpty
                ? newTasks.last.createdAt
                : currentState.lastDoc,
            hasReachedMax: newTasks.length < _pageSize,
            isLoadingMore: false,
          ),
        );
      },
    );
  }

  Future<void> _onStatusFilterChanged(
    StatusFilterChanged event,
    Emitter<AdminTasksState> emit,
  ) async {
    add(
      LoadAdminTasksRequested(
        organizationId: event.organizationId,
        companyId: event.companyId,
        status: event.status,
        adminId: event.adminId,
        adminRoleName: event.adminRoleName,
      ),
    );
  }

  Future<void> _onUpdateStatus(
    AdminTaskStatusUpdateRequested event,
    Emitter<AdminTasksState> emit,
  ) async {
    final result = await updateTaskStatus(
      event.organizationId,
      event.taskId,
      event.newStatus,
      notes: event.notes,
    );

    result.fold(
      (failure) => emit(
        AdminTasksError(
          message: failure.message,
          statusFilter: (state is AdminTasksLoaded)
              ? (state as AdminTasksLoaded).statusFilter
              : (state is AdminTasksLoading)
              ? (state as AdminTasksLoading).statusFilter
              : null,
        ),
      ),
      (_) {
        if (state is AdminTasksLoaded) {
          final currentState = state as AdminTasksLoaded;
          // Update local state for immediate feedback
          final updatedTasks = currentState.tasks.map((task) {
            if (task.uid == event.taskId) {
              return task.copyWith(status: event.newStatus);
            }
            return task;
          }).toList();

          emit(currentState.copyWith(tasks: updatedTasks));
        }
      },
    );
  }

  Future<void> _onUpdateTask(
    UpdateTaskRequested event,
    Emitter<AdminTasksState> emit,
  ) async {
    final result = await updateTask(event.organizationId, event.task);

    result.fold(
      (failure) => emit(
        AdminTasksError(
          message: failure.message,
          statusFilter: (state is AdminTasksLoaded)
              ? (state as AdminTasksLoaded).statusFilter
              : (state is AdminTasksLoading)
              ? (state as AdminTasksLoading).statusFilter
              : null,
        ),
      ),
      (_) {
        if (state is AdminTasksLoaded) {
          final currentState = state as AdminTasksLoaded;
          final updatedTasks = currentState.tasks.map((t) {
            return t.uid == event.task.uid ? event.task : t;
          }).toList();
          emit(currentState.copyWith(tasks: updatedTasks));
        }
      },
    );
  }
}
