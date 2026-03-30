import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';

class DeleteTask {
  final TaskRepository repository;

  DeleteTask(this.repository);

  Future<Either<Failure, void>> call(
    String organizationId,
    String taskId,
  ) async {
    return await repository.deleteTask(organizationId, taskId);
  }
}
