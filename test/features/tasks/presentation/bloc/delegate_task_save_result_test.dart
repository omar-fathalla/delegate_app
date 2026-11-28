import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_completions.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_delegate_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_state.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGet extends Mock implements GetDelegateTasks {}

class _MockStatus extends Mock implements UpdateTaskStatus {}

class _MockUpdate extends Mock implements UpdateTask {}

/// Completions whose save is refused by the rules.
class _DeniedCompletions extends TaskCompletions {
  _DeniedCompletions() : super(FakeFirebaseFirestore());

  @override
  Future<void> save({
    required String organizationId,
    required String taskId,
    required String selfId,
    required TaskStatus status,
    String? notes,
  }) async {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
  }
}

/// TAS-411: the task details screen has its own DelegateTasksBloc (nothing
/// loaded). It now waits for the bloc's answer before saying «saved»: the
/// bloc must say success or error, never stay silent.
void main() {
  TaskEntity task(String id, {String to = 'all'}) => TaskEntity(
        uid: id,
        title: 't',
        description: 'd',
        priority: TaskPriority.medium,
        status: TaskStatus.inProgress,
        assignedTo: to,
        assignedToName: 'الكل',
        companyId: 'c1',
        createdBy: 'sup',
        createdByName: 'Sup',
        dueDate: DateTime(2026, 12, 1),
        createdAt: DateTime(2026, 11, 28),
      );

  setUpAll(() {
    registerFallbackValue(task('x'));
  });

  DelegateTasksBloc bloc({TaskCompletions? comp, UpdateTask? update}) => DelegateTasksBloc(
        getDelegateTasks: _MockGet(),
        updateTaskStatus: _MockStatus(),
        updateTask: update ?? _MockUpdate(),
        completions: comp ?? TaskCompletions(FakeFirebaseFirestore()),
        selfId: () => 'del-1',
      );

  Future<DelegateTasksState> send(DelegateTasksBloc b, TaskEntity t) async {
    final next = b.stream.first;
    b.add(UpdateTaskRequestedDelegate(organizationId: 'o1', task: t));
    return next.timeout(const Duration(seconds: 2));
  }

  test('shared task saved: success with the new status', () async {
    final b = bloc();
    final s = await send(b, task('t1'));
    expect(s, isA<TaskStatusUpdateSuccess>());
    expect((s as TaskStatusUpdateSuccess).newStatus, TaskStatus.inProgress);
    await b.close();
  });

  test('shared task refused by the rules: an error, not a silent success', () async {
    final b = bloc(comp: _DeniedCompletions());
    final s = await send(b, task('t2'));
    expect(s, isA<DelegateTasksError>());
    expect((s as DelegateTasksError).message, contains('تعذّر حفظ'));
    await b.close();
  });

  test('own task saved: success; refused: error', () async {
    final ok = _MockUpdate();
    when(() => ok(any(), any())).thenAnswer((_) async => const Right(null));
    final b1 = bloc(update: ok);
    expect(await send(b1, task('t3', to: 'del-1')), isA<TaskStatusUpdateSuccess>());
    await b1.close();

    final bad = _MockUpdate();
    when(() => bad(any(), any()))
        .thenAnswer((_) async => const Left(ServerFailure('refused')));
    final b2 = bloc(update: bad);
    expect(await send(b2, task('t4', to: 'del-1')), isA<DelegateTasksError>());
    await b2.close();
  });
}
