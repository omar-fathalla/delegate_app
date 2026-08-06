import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_admin_tasks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTaskRepository extends Mock implements TaskRepository {}

void main() {
  late GetAdminTasks usecase;
  late MockTaskRepository mockTaskRepository;

  setUpAll(() {
    registerFallbackValue(TaskStatus.pending);
  });

  setUp(() {
    mockTaskRepository = MockTaskRepository();
    usecase = GetAdminTasks(mockTaskRepository);
  });

  final tTasks = [
    TaskEntity(
      uid: 'task1',
      title: 'Task 1',
      description: 'Desc',
      priority: TaskPriority.low,
      status: TaskStatus.pending,
      assignedTo: 'delegate1',
      assignedToName: 'Del 1',
      companyId: 'comp1',
      createdBy: 'admin',
      createdByName: 'Admin',
      dueDate: DateTime.now(),
      createdAt: DateTime.now(),
    ),
  ];

  test('should get admin tasks from the repository', () async {
    // Arrange
    when(() => mockTaskRepository.getAdminTasks(any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
        .thenAnswer((_) async => Right(tTasks));

    // Act
    final result = await usecase('org1', 'comp1');

    // Assert
    expect(result, Right(tTasks));
    verify(() => mockTaskRepository.getAdminTasks('org1', 'comp1')).called(1);
    verifyNoMoreInteractions(mockTaskRepository);
  });
}
