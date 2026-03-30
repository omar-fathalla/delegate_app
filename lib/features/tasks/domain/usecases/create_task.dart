import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';

class CreateTask {
  final TaskRepository repository;

  CreateTask(this.repository);

  Future<Either<Failure, TaskEntity>> call(
    String organizationId,
    TaskEntity task,
  ) {
    return repository.createTask(organizationId, task);
  }
}
