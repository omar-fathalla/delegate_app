import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';

class UpdateTaskStatus {
  final TaskRepository repository;

  UpdateTaskStatus(this.repository);

  Future<Either<Failure, void>> call(
    String organizationId,
    String taskId,
    TaskStatus newStatus, {
    String? notes,
    String? completedBy,
  }) {
    return repository.updateTaskStatus(
      organizationId,
      taskId,
      newStatus,
      notes: notes,
      completedBy: completedBy,
    );
  }
}
