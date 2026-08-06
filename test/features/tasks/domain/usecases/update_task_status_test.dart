import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTaskRepository extends Mock implements TaskRepository {}

void main() {
  late UpdateTaskStatus usecase;
  late MockTaskRepository mockTaskRepository;

  setUpAll(() {
    registerFallbackValue(TaskStatus.pending);
  });

  setUp(() {
    mockTaskRepository = MockTaskRepository();
    usecase = UpdateTaskStatus(mockTaskRepository);
  });

  test('should update task status via repository', () async {
    // Arrange
    when(() => mockTaskRepository.updateTaskStatus(any(), any(), any(), notes: any(named: 'notes'), completedBy: any(named: 'completedBy')))
        .thenAnswer((_) async => const Right(null));

    // Act
    final result = await usecase('org1', 'task1', TaskStatus.completed, notes: 'Done');

    // Assert
    expect(result, const Right(null));
    verify(() => mockTaskRepository.updateTaskStatus('org1', 'task1', TaskStatus.completed, notes: 'Done')).called(1);
    verifyNoMoreInteractions(mockTaskRepository);
  });
}
