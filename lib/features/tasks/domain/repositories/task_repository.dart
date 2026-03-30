import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class TaskRepository {
  Future<Either<Failure, TaskEntity>> createTask(
    String organizationId,
    TaskEntity task,
  );

  Future<Either<Failure, void>> updateTaskStatus(
    String organizationId,
    String taskId,
    TaskStatus newStatus, {
    String? notes,
    String? completedBy,
  });

  Future<Either<Failure, List<TaskEntity>>> getAdminTasks(
    String organizationId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  });

  Future<Either<Failure, List<TaskEntity>>> getDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  });

  Future<Either<Failure, void>> updateTask(
    String organizationId,
    TaskEntity task,
  );

  Future<Either<Failure, void>> deleteTask(
    String organizationId,
    String taskId,
  );
}
