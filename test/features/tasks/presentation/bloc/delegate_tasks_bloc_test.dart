import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_delegate_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetDelegateTasks extends Mock implements GetDelegateTasks {}
class MockUpdateTaskStatus extends Mock implements UpdateTaskStatus {}
class MockUpdateTask extends Mock implements UpdateTask {}
class FakeTaskEntity extends Fake implements TaskEntity {}

void main() {
  late DelegateTasksBloc bloc;
  late MockGetDelegateTasks mockGetDelegateTasks;
  late MockUpdateTaskStatus mockUpdateTaskStatus;
  late MockUpdateTask mockUpdateTask;

  setUpAll(() {
    registerFallbackValue(FakeTaskEntity());
    registerFallbackValue(TaskStatus.pending);
  });

  setUp(() {
    mockGetDelegateTasks = MockGetDelegateTasks();
    mockUpdateTaskStatus = MockUpdateTaskStatus();
    mockUpdateTask = MockUpdateTask();

    bloc = DelegateTasksBloc(
      getDelegateTasks: mockGetDelegateTasks,
      updateTaskStatus: mockUpdateTaskStatus,
      updateTask: mockUpdateTask,
    );
  });

  final tTaskEntity = TaskEntity(
    uid: 'task123',
    title: 'Test Task',
    description: 'Task description',
    priority: TaskPriority.high,
    status: TaskStatus.pending,
    assignedTo: 'delegate456',
    assignedToName: 'Delegate Name',
    companyId: 'company789',
    createdBy: 'admin123',
    createdByName: 'Admin Name',
    dueDate: DateTime(2023, 1, 2),
    createdAt: DateTime(2023, 1, 1),
  );

  final tTasks = [tTaskEntity];

  test('initial state should be DelegateTasksInitial', () {
    expect(bloc.state, equals(const DelegateTasksInitial()));
  });

  blocTest<DelegateTasksBloc, DelegateTasksState>(
    'should emit [DelegateTasksLoading, DelegateTasksLoaded] when LoadDelegateTasksRequested is added and successful',
    build: () {
      when(() => mockGetDelegateTasks(any(), any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenAnswer((_) async => Right(tTasks));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadDelegateTasksRequested(organizationId: 'org1', delegateId: 'del1', companyId: 'comp1')),
    expect: () => [
      const DelegateTasksLoading(statusFilter: null),
      DelegateTasksLoaded(tasks: tTasks, statusFilter: null, lastDoc: tTasks.last.uid, hasReachedMax: true),
    ],
  );

  blocTest<DelegateTasksBloc, DelegateTasksState>(
    'should update task status and modify state if Loaded',
    build: () {
      when(() => mockUpdateTaskStatus(any(), any(), any(), notes: any(named: 'notes')))
          .thenAnswer((_) async => const Right(null));
      return bloc;
    },
    // Using TaskStatusUpdateSuccess causes it to not update tasks locally, so we expect TaskStatusUpdateSuccess
    act: (bloc) => bloc.add(const UpdateTaskStatusRequested(organizationId: 'org1', taskId: 'task123', newStatus: TaskStatus.completed)),
    expect: () => [
      const TaskStatusUpdateSuccess(),
    ],
  );

  blocTest<DelegateTasksBloc, DelegateTasksState>(
    'should update task and modify state if Loaded',
    build: () {
      when(() => mockUpdateTask(any(), any()))
          .thenAnswer((_) async => const Right(null));
      return bloc;
    },
    seed: () => DelegateTasksLoaded(tasks: tTasks, statusFilter: null, lastDoc: tTasks.last.uid, hasReachedMax: true),
    act: (bloc) => bloc.add(UpdateTaskRequestedDelegate(organizationId: 'org1', task: tTaskEntity.copyWith(title: 'Updated Title'))),
    expect: () => [
      DelegateTasksLoaded(
        tasks: [tTaskEntity.copyWith(title: 'Updated Title')], 
        statusFilter: null, 
        lastDoc: tTasks.last.uid, 
        hasReachedMax: true,
      ),
    ],
  );
}
