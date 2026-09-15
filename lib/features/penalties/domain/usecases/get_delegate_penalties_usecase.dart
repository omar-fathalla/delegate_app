import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';

class GetDelegatePenaltiesUseCase {
  final PenaltyRepository repository;

  GetDelegatePenaltiesUseCase(this.repository);

  Future<Either<Failure, List<PenaltyEntity>>> call({
    required String delegateId,
    String? companyId,
    String? phoneNumber,
    String? fullName,
  }) async {
    return await repository.getDelegatePenalties(
      delegateId: delegateId,
      companyId: companyId,
      phoneNumber: phoneNumber,
      fullName: fullName,
    );
  }
}
