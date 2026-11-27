import 'package:dartz/dartz.dart';
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

/// TAS-368: a delegate's progress on a shared task is its own.
void main() {
  late FakeFirebaseFirestore fs;
  late TaskCompletions comp;

  TaskEntity task(String id, {String to = 'all', TaskStatus status = TaskStatus.pending}) => TaskEntity(
        uid: id,
        title: 't',
        description: 'd',
        priority: TaskPriority.medium,
        status: status,
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
    registerFallbackValue(TaskStatus.pending);
  });

  setUp(() {
    fs = FakeFirebaseFirestore();
    comp = TaskCompletions(fs);
  });

  test('shared keys', () {
    expect(TaskCompletions.isShared('all'), isTrue);
    expect(TaskCompletions.isShared('all_marketing_promotion'), isTrue);
    expect(TaskCompletions.isShared('del-1'), isFalse);
  });

  test('save writes the caller own doc; a delegate never cancels', () async {
    await comp.save(organizationId: 'o1', taskId: 't1', selfId: 'del-1', status: TaskStatus.completed, notes: 'تم');
    final d = (await fs.doc('organizations/o1/tasks/t1/completions/del-1').get()).data()!;
    expect(d['status'], 'completed');
    expect(d['notes'], 'تم');
    expect(d.containsKey('completedAt'), isTrue);
    expect(
      () => comp.save(organizationId: 'o1', taskId: 't1', selfId: 'del-1', status: TaskStatus.cancelled),
      throwsArgumentError,
    );
  });

  test('overlay: a colleague done is not mine; the sender cancel stays', () async {
    await comp.save(organizationId: 'o1', taskId: 't1', selfId: 'del-2', status: TaskStatus.completed);
    await comp.save(organizationId: 'o1', taskId: 't2', selfId: 'del-1', status: TaskStatus.inProgress);
    final out = await comp.overlayMine(organizationId: 'o1', selfId: 'del-1', tasks: [
      task('t1', status: TaskStatus.completed), // shared doc closed by an old build
      task('t2'),
      task('t3', status: TaskStatus.cancelled),
      task('t4', to: 'del-1', status: TaskStatus.inProgress),
    ]);
    expect(out[0].status, TaskStatus.pending);
    expect(out[1].status, TaskStatus.inProgress);
    expect(out[2].status, TaskStatus.cancelled);
    expect(out[3].status, TaskStatus.inProgress, reason: 'individual task untouched');
  });

  test('completed count for staff', () async {
    await comp.save(organizationId: 'o1', taskId: 't1', selfId: 'a', status: TaskStatus.completed);
    await comp.save(organizationId: 'o1', taskId: 't1', selfId: 'b', status: TaskStatus.inProgress);
    await comp.save(organizationId: 'o1', taskId: 't1', selfId: 'c', status: TaskStatus.completed);
    expect(await comp.completedCount(organizationId: 'o1', taskId: 't1'), 2);
  });

  test('bloc: saving a shared task writes the completion, never the shared doc', () async {
    final update = _MockUpdate();
    final bloc = DelegateTasksBloc(
      getDelegateTasks: _MockGet(),
      updateTaskStatus: _MockStatus(),
      updateTask: update,
      completions: comp,
      selfId: () => 'del-1',
    );
    bloc.add(UpdateTaskRequestedDelegate(
      organizationId: 'o1',
      task: task('t9').copyWith(status: TaskStatus.completed, notes: 'خلصت'),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verifyNever(() => update(any(), any()));
    final d = (await fs.doc('organizations/o1/tasks/t9/completions/del-1').get()).data()!;
    expect(d['status'], 'completed');
    expect(d['notes'], 'خلصت');
    await bloc.close();
  });

  test('bloc: an individual task still goes through updateTask', () async {
    final update = _MockUpdate();
    when(() => update(any(), any())).thenAnswer((_) async => const Right(null));
    final bloc = DelegateTasksBloc(
      getDelegateTasks: _MockGet(),
      updateTaskStatus: _MockStatus(),
      updateTask: update,
      completions: comp,
      selfId: () => 'del-1',
    );
    bloc.add(UpdateTaskRequestedDelegate(organizationId: 'o1', task: task('t8', to: 'del-1')));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(() => update('o1', any())).called(1);
    expect(bloc.state, isNot(isA<DelegateTasksError>()));
    await bloc.close();
  });
}
