import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/data/repositories/task_repository_impl.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTaskRemoteDataSource extends Mock implements TaskRemoteDataSource {}

class FakeTaskModel extends Fake implements TaskModel {}

void main() {
  late TaskRepositoryImpl repository;
  late MockTaskRemoteDataSource mockRemoteDataSource;

  setUpAll(() {
    registerFallbackValue(FakeTaskModel());
    registerFallbackValue(TaskStatus.pending);
  });

  setUp(() {
    mockRemoteDataSource = MockTaskRemoteDataSource();
    repository = TaskRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  final tTaskEntity = TaskEntity(
    uid: 'task123',
    title: 'Test Task',
    description: 'Task description',
    priority: TaskPriority.high,
    status: TaskStatus.completed,
    assignedTo: 'delegate456',
    assignedToName: 'Delegate Name',
    companyId: 'company789',
    createdBy: 'admin123',
    createdByName: 'Admin Name',
    dueDate: DateTime(2023, 1, 2),
    createdAt: DateTime(2023, 1, 1),
  );

  final tTaskModel = TaskModel.fromEntity(tTaskEntity);

  group('createTask', () {
    test('should return created TaskEntity when remote data source is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.createTask(any(), any()))
          .thenAnswer((_) async => tTaskModel);

      // Act
      final result = await repository.createTask('org123', tTaskEntity);

      // Assert
      expect(result, equals(Right<Failure, TaskEntity>(tTaskModel)));
      verify(() => mockRemoteDataSource.createTask('org123', any())).called(1);
    });

    test('should return ServerFailure when remote data source throws ServerException', () async {
      // Arrange
      when(() => mockRemoteDataSource.createTask(any(), any()))
          .thenThrow(ServerException('Error creating task'));

      // Act
      final result = await repository.createTask('org123', tTaskEntity);

      // Assert
      expect(result, equals(const Left(ServerFailure('Error creating task'))));
    });
  });

  group('updateTaskStatus', () {
    test('should return void when update is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.updateTaskStatus(any(), any(), any(), notes: any(named: 'notes'), completedBy: any(named: 'completedBy')))
          .thenAnswer((_) async => Future.value());

      // Act
      final result = await repository.updateTaskStatus('org123', 'task123', TaskStatus.completed);

      // Assert
      expect(result, equals(const Right(null)));
    });

    test('should return ServerFailure when update fails', () async {
      // Arrange
      when(() => mockRemoteDataSource.updateTaskStatus(any(), any(), any(), notes: any(named: 'notes'), completedBy: any(named: 'completedBy')))
          .thenThrow(Exception());

      // Act
      final result = await repository.updateTaskStatus('org123', 'task123', TaskStatus.completed);

      // Assert
      expect(result, equals(const Left(ServerFailure('حدث خطأ أثناء تحديث حالة المهمة.'))));
    });
  });

  group('getAdminTasks', () {
    test('should return list of TaskEntity on success', () async {
      // Arrange
      when(() => mockRemoteDataSource.getAdminTasks(any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenAnswer((_) async => [tTaskModel]);

      // Act
      final result = await repository.getAdminTasks('org123', 'company123');

      // Assert
      result.fold(
        (l) => fail('Should return Right'),
        (r) => expect(r, equals([tTaskModel])),
      );
    });

    test('should return ServerFailure on ServerException', () async {
      // Arrange
      when(() => mockRemoteDataSource.getAdminTasks(any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenThrow(ServerException('Failed to get tasks'));

      // Act
      final result = await repository.getAdminTasks('org123', 'company123');

      // Assert
      expect(result, equals(const Left(ServerFailure('Failed to get tasks'))));
    });
  });

  group('getDelegateTasks', () {
    test('should return list of TaskEntity on success', () async {
      // Arrange
      when(() => mockRemoteDataSource.getDelegateTasks(any(), any(), any(), status: any(named: 'status'), limit: any(named: 'limit'), lastDoc: any(named: 'lastDoc')))
          .thenAnswer((_) async => [tTaskModel]);

      // Act
      final result = await repository.getDelegateTasks('org123', 'delegate123', 'company123');

      // Assert
      result.fold(
        (l) => fail('Should return Right'),
        (r) => expect(r, equals([tTaskModel])),
      );
    });
  });

  group('updateTask', () {
    test('should return void on success', () async {
      // Arrange
      when(() => mockRemoteDataSource.updateTask(any(), any()))
          .thenAnswer((_) async => Future.value());

      // Act
      final result = await repository.updateTask('org123', tTaskEntity);

      // Assert
      expect(result, equals(const Right(null)));
    });
  });

  group('deleteTask', () {
    test('should return void on success', () async {
      // Arrange
      when(() => mockRemoteDataSource.deleteTask(any(), any()))
          .thenAnswer((_) async => Future.value());

      // Act
      final result = await repository.deleteTask('org123', 'task123');

      // Assert
      expect(result, equals(const Right(null)));
    });

    test('should return ServerFailure on general exception', () async {
      // Arrange
      when(() => mockRemoteDataSource.deleteTask(any(), any()))
          .thenThrow(Exception());

      // Act
      final result = await repository.deleteTask('org123', 'task123');

      // Assert
      expect(result, equals(const Left(ServerFailure('حدث خطأ أثناء حذف المهمة.'))));
    });
  });
}
