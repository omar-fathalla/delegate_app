import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

/// Uploads every queued audit of the given delegate UID. Returns synced count.
class SyncPendingPrivateLabelAudits implements UseCase<int, String> {
  final PrivateLabelRepository repository;

  SyncPendingPrivateLabelAudits(this.repository);

  @override
  Future<Either<Failure, int>> call(String delegateUid) {
    return repository.syncPendingAudits(delegateUid);
  }
}
