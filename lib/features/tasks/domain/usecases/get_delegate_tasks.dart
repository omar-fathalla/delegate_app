import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';

class GetDelegateTasks {
  final TaskRepository repository;

  GetDelegateTasks(this.repository);

  Future<Either<Failure, List<TaskEntity>>> call(
    String organizationId,
    String delegateId,
    String companyId,
    String delegateRoleName, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) {
    return repository.getDelegateTasks(
      organizationId,
      delegateId,
      companyId,
      delegateRoleName,
      status: status,
      limit: limit,
      lastDoc: lastDoc,
    );
  }
}
