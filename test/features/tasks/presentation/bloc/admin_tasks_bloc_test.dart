import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_admin_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetAdminTasks extends Mock implements GetAdminTasks {}
class MockUpdateTaskStatus extends Mock implements UpdateTaskStatus {}
class MockUpdateTask extends Mock implements UpdateTask {}
class FakeTaskEntity extends Fake implements TaskEntity {}

void main() {
  late AdminTasksBloc bloc;
  late MockGetAdminTasks mockGetAdminTasks;
  late MockUpdateTaskStatus mockUpdateTaskStatus;
  late MockUpdateTask mockUpdateTask;

  setUpAll(() {
    registerFallbackValue(FakeTaskEntity());
    registerFallbackValue(TaskStatus.pending);
  });

  setUp(() {
    mockGetAdminTasks = MockGetAdminTasks();
    mockUpdateTaskStatus = MockUpdateTaskStatus();
    mockUpdateTask = MockUpdateTask();

    bloc = AdminTasksBloc(
      getAdminTasks: mockGetAdminTasks,
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

  test('initial state should be AdminTasksInitial', () {
    expect(bloc.state, equals(const AdminTasksInitial()));
  });

  blocTest<AdminTasksBloc, AdminTasksState>(
    'should emit [AdminTasksLoading, AdminTasksLoaded] when LoadAdminTasksRequested is added and successful',
    build: () {
      when(() => mockGetAdminTasks(any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenAnswer((_) async => Right(tTasks));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadAdminTasksRequested(organizationId: 'org1', companyId: 'comp1')),
    expect: () => [
      const AdminTasksLoading(statusFilter: null),
      AdminTasksLoaded(tasks: tTasks, statusFilter: null, lastDoc: tTasks.last.createdAt, hasReachedMax: true), // 1 item < _pageSize(20)
    ],
  );

  blocTest<AdminTasksBloc, AdminTasksState>(
    'should emit [AdminTasksLoading, AdminTasksError] when LoadAdminTasksRequested fails',
    build: () {
      when(() => mockGetAdminTasks(any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadAdminTasksRequested(organizationId: 'org1', companyId: 'comp1')),
    expect: () => [
      const AdminTasksLoading(statusFilter: null),
      const AdminTasksError(message: 'Error', statusFilter: null),
    ],
  );

  blocTest<AdminTasksBloc, AdminTasksState>(
    'should trigger load tasks on StatusFilterChanged',
    build: () {
      when(() => mockGetAdminTasks(any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenAnswer((_) async => Right(tTasks));
      return bloc;
    },
    act: (bloc) => bloc.add(const StatusFilterChanged(organizationId: 'org1', companyId: 'comp1', status: TaskStatus.completed)),
    expect: () => [
      const AdminTasksLoading(statusFilter: TaskStatus.completed),
      AdminTasksLoaded(tasks: tTasks, statusFilter: TaskStatus.completed, lastDoc: tTasks.last.createdAt, hasReachedMax: true),
    ],
  );

  blocTest<AdminTasksBloc, AdminTasksState>(
    'should update task status and modify state if Loaded',
    build: () {
      when(() => mockUpdateTaskStatus(any(), any(), any(), notes: any(named: 'notes')))
          .thenAnswer((_) async => const Right(null));
      return bloc;
    },
    seed: () => AdminTasksLoaded(tasks: tTasks, statusFilter: null, lastDoc: tTasks.last.createdAt, hasReachedMax: true),
    act: (bloc) => bloc.add(const AdminTaskStatusUpdateRequested(organizationId: 'org1', taskId: 'task123', newStatus: TaskStatus.completed)),
    expect: () => [
      AdminTasksLoaded(
        tasks: [tTaskEntity.copyWith(status: TaskStatus.completed)], 
        statusFilter: null, 
        lastDoc: tTasks.last.createdAt, 
        hasReachedMax: true,
      ),
    ],
  );

  blocTest<AdminTasksBloc, AdminTasksState>(
    'should update task and modify state if Loaded',
    build: () {
      when(() => mockUpdateTask(any(), any()))
          .thenAnswer((_) async => const Right(null));
      return bloc;
    },
    seed: () => AdminTasksLoaded(tasks: tTasks, statusFilter: null, lastDoc: tTasks.last.createdAt, hasReachedMax: true),
    act: (bloc) => bloc.add(UpdateTaskRequested(organizationId: 'org1', task: tTaskEntity.copyWith(title: 'Updated Title'))),
    expect: () => [
      AdminTasksLoaded(
        tasks: [tTaskEntity.copyWith(title: 'Updated Title')], 
        statusFilter: null, 
        lastDoc: tTasks.last.createdAt, 
        hasReachedMax: true,
      ),
    ],
  );
}
