import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';

class TaskRepositoryImpl implements TaskRepository {
  final TaskRemoteDataSource remoteDataSource;

  TaskRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, TaskEntity>> createTask(
    String organizationId,
    TaskEntity task,
  ) async {
    try {
      final taskModel = TaskModel.fromEntity(task);
      final result = await remoteDataSource.createTask(
        organizationId,
        taskModel,
      );
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ غير متوقع: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> updateTaskStatus(
    String organizationId,
    String taskId,
    TaskStatus newStatus, {
    String? notes,
    String? completedBy,
  }) async {
    try {
      await remoteDataSource.updateTaskStatus(
        organizationId,
        taskId,
        newStatus,
        notes: notes,
        completedBy: completedBy,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ أثناء تحديث حالة المهمة.'));
    }
  }

  @override
  Future<Either<Failure, List<TaskEntity>>> getAdminTasks(
    String organizationId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) async {
    try {
      final result = await remoteDataSource.getAdminTasks(
        organizationId,
        companyId,
        status: status,
        limit: limit,
        lastDoc: lastDoc,
      );
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ أثناء جلب المهام: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, List<TaskEntity>>> getDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) async {
    try {
      final result = await remoteDataSource.getDelegateTasks(
        organizationId,
        delegateId,
        companyId,
        status: status,
        limit: limit,
        lastDoc: lastDoc,
      );
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(
        ServerFailure('حدث خطأ أثناء جلب المهام الخاصة بك: ${e.toString()}'),
      );
    }
  }

  @override
  Future<Either<Failure, void>> updateTask(
    String organizationId,
    TaskEntity task,
  ) async {
    try {
      await remoteDataSource.updateTask(
        organizationId,
        TaskModel.fromEntity(task),
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteTask(
    String organizationId,
    String taskId,
  ) async {
    try {
      await remoteDataSource.deleteTask(organizationId, taskId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('حدث خطأ أثناء حذف المهمة.'));
    }
  }
}
