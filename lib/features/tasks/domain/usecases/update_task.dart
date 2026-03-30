import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class UpdateTask {
  final TaskRepository repository;

  UpdateTask(this.repository);

  Future<Either<Failure, void>> call(String organizationId, TaskEntity task) {
    return repository.updateTask(organizationId, task);
  }
}
