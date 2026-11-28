import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/security/delegate_identity.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_completions.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
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

  /// TAS-368: the delegate's own progress on shared tasks.
  final TaskCompletions? _completions;
  final String? Function() _selfId;

  DelegateTasksBloc({
    required this.getDelegateTasks,
    required this.updateTaskStatus,
    required this.updateTask,
    TaskCompletions? completions,
    String? Function()? selfId,
  }) : _completions = completions,
       _selfId = selfId ?? DelegateIdentity.current,
       super(DelegateTasksInitial()) {
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
      event.delegateRoleName,
      status: event.status,
      limit: 20,
    );
    final shown = await result.fold(
      (_) async => null,
      (tasks) => _withMine(event.organizationId, tasks),
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
          tasks: shown ?? tasks,
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
      event.delegateRoleName,
      status: currentState.statusFilter,
      lastDoc: currentState.lastDoc,
      limit: 20,
    );

    final shownMore = await result.fold(
      (_) async => null,
      (tasks) => _withMine(event.organizationId, tasks),
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
          tasks: List.of(currentState.tasks)..addAll(shownMore ?? newTasks),
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
        delegateRoleName: event.delegateRoleName,
        status: event.status,
      ),
    );
  }

  Future<void> _onUpdateStatus(
    UpdateTaskStatusRequested event,
    Emitter<DelegateTasksState> emit,
  ) async {
    // TAS-368: a shared task is marked for this delegate only.
    final current = state;
    final shared = current is DelegateTasksLoaded
        ? current.tasks.where((t) => t.uid == event.taskId && TaskCompletions.isShared(t.assignedTo))
        : const <TaskEntity>[];
    if (shared.isNotEmpty) {
      final error = await _saveMine(event.organizationId, shared.first, event.newStatus, event.notes);
      if (error != null) {
        emit(DelegateTasksError(
          message: error,
          statusFilter: (current as DelegateTasksLoaded).statusFilter,
        ));
        return;
      }
      emit(TaskStatusUpdateSuccess(newStatus: event.newStatus));
      return;
    }
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
        emit(TaskStatusUpdateSuccess(newStatus: event.newStatus));
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
    if (TaskCompletions.isShared(event.task.assignedTo)) {
      // TAS-368: never the shared doc; this delegate's own progress only.
      final error = await _saveMine(
        event.organizationId,
        event.task,
        event.task.status,
        event.task.notes,
      );
      if (error != null) {
        emit(DelegateTasksError(
          message: error,
          statusFilter: (state is DelegateTasksLoaded)
              ? (state as DelegateTasksLoaded).statusFilter
              : null,
        ));
        return;
      }
      if (state is DelegateTasksLoaded) {
        final currentState = state as DelegateTasksLoaded;
        emit(currentState.copyWith(
          tasks: currentState.tasks
              .map((t) => t.uid == event.task.uid ? event.task : t)
              .toList(),
        ));
      } else {
        // TAS-411: the details screen has its own bloc (no list loaded);
        // it waits for this before saying the task was saved.
        emit(TaskStatusUpdateSuccess(newStatus: event.task.status));
      }
      return;
    }
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
        } else {
          emit(TaskStatusUpdateSuccess(newStatus: event.task.status));
        }
      },
    );
  }

  TaskCompletions get _comp =>
      _completions ?? TaskCompletions(FirebaseFirestore.instance);

  /// Shared tasks shown with this delegate's own progress (TAS-368).
  Future<List<TaskEntity>> _withMine(String org, List<TaskEntity> tasks) async {
    final self = _selfId();
    if (self == null || !tasks.any((t) => TaskCompletions.isShared(t.assignedTo))) {
      return tasks;
    }
    return _comp.overlayMine(organizationId: org, selfId: self, tasks: tasks);
  }

  /// Saves the delegate's progress on a shared task to its own completion
  /// doc. Returns an error message, or null on success.
  Future<String?> _saveMine(String org, TaskEntity task, TaskStatus status, String? notes) async {
    final self = _selfId();
    if (self == null) return 'سجّل دخول تاني وجرّب.';
    try {
      await _comp.save(
        organizationId: org,
        taskId: task.uid,
        selfId: self,
        status: status,
        notes: notes,
      );
      return null;
    } on FirebaseException catch (e) {
      return e.code == 'permission-denied' && task.proofRequired
          ? 'محتاج صورة: المهمة دي لازم صورة تثبت إنك عملتها.'
          : 'تعذّر حفظ حالة المهمة. حاول تاني.';
    } catch (_) {
      return 'تعذّر حفظ حالة المهمة. حاول تاني.';
    }
  }
}
