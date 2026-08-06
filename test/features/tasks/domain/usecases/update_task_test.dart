import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTaskRepository extends Mock implements TaskRepository {}
class FakeTaskEntity extends Fake implements TaskEntity {}

void main() {
  late UpdateTask usecase;
  late MockTaskRepository mockTaskRepository;

  setUpAll(() {
    registerFallbackValue(FakeTaskEntity());
  });

  setUp(() {
    mockTaskRepository = MockTaskRepository();
    usecase = UpdateTask(mockTaskRepository);
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

  test('should update task via repository', () async {
    // Arrange
    when(() => mockTaskRepository.updateTask(any(), any()))
        .thenAnswer((_) async => const Right(null));

    // Act
    final result = await usecase('org123', tTaskEntity);

    // Assert
    expect(result, const Right(null));
    verify(() => mockTaskRepository.updateTask('org123', tTaskEntity)).called(1);
    verifyNoMoreInteractions(mockTaskRepository);
  });
}
