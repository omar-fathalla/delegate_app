import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';
import 'package:delegate_app/features/tasks/domain/usecases/delete_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTaskRepository extends Mock implements TaskRepository {}

void main() {
  late DeleteTask usecase;
  late MockTaskRepository mockTaskRepository;

  setUp(() {
    mockTaskRepository = MockTaskRepository();
    usecase = DeleteTask(mockTaskRepository);
  });

  test('should delete task from the repository', () async {
    // Arrange
    when(() => mockTaskRepository.deleteTask(any(), any()))
        .thenAnswer((_) async => const Right(null));

    // Act
    final result = await usecase('org123', 'task123');

    // Assert
    expect(result, const Right(null));
    verify(() => mockTaskRepository.deleteTask('org123', 'task123')).called(1);
    verifyNoMoreInteractions(mockTaskRepository);
  });
}
