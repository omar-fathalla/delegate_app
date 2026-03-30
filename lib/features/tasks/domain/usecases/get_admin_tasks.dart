import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';

class GetAdminTasks {
  final TaskRepository repository;

  GetAdminTasks(this.repository);

  Future<Either<Failure, List<TaskEntity>>> call(
    String organizationId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) {
    return repository.getAdminTasks(
      organizationId,
      companyId,
      status: status,
      limit: limit,
      lastDoc: lastDoc,
    );
  }
}
