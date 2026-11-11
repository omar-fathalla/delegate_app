import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';

class GetCompanyPenaltiesUseCase {
  final PenaltyRepository repository;

  GetCompanyPenaltiesUseCase(this.repository);

  Future<Either<Failure, List<PenaltyEntity>>> call(
    String companyId, {
    String? organizationId,
  }) async {
    return await repository.getCompanyPenalties(
      companyId,
      organizationId: organizationId,
    );
  }
}
