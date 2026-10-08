import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class GetPendingPrivateLabelAudits
    implements UseCase<List<PrivateLabelAuditDraft>, String> {
  final PrivateLabelRepository repository;

  GetPendingPrivateLabelAudits(this.repository);

  @override
  Future<Either<Failure, List<PrivateLabelAuditDraft>>> call(String delegateUid) {
    return repository.getPendingAudits(delegateUid);
  }
}
