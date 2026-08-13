import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';

class UpdatePenaltyStatusUseCase {
  final PenaltyRepository repository;

  UpdatePenaltyStatusUseCase(this.repository);

  Future<Either<Failure, Unit>> call({
    required String penaltyId,
    required PenaltyStatus status,
    String? rejectionReason,
    String? reviewerName,
  }) async {
    return await repository.updatePenaltyStatus(
      penaltyId: penaltyId,
      status: status,
      rejectionReason: rejectionReason,
      reviewerName: reviewerName,
    );
  }
}
