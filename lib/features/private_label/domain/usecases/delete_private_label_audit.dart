import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class DeleteAuditParams {
  final String organizationUID;
  final String auditId;
  final String delegateUid;
  final String date;

  const DeleteAuditParams({
    required this.organizationUID,
    required this.auditId,
    required this.delegateUid,
    required this.date,
  });
}

class DeletePrivateLabelAudit implements UseCase<Unit, DeleteAuditParams> {
  final PrivateLabelRepository repository;

  DeletePrivateLabelAudit(this.repository);

  @override
  Future<Either<Failure, Unit>> call(DeleteAuditParams params) {
    return repository.deleteAudit(
      organizationUID: params.organizationUID,
      auditId: params.auditId,
      delegateUid: params.delegateUid,
      date: params.date,
    );
  }
}
