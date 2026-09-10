import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';

class UpdatePenaltyUseCase {
  final PenaltyRepository repository;

  UpdatePenaltyUseCase(this.repository);

  Future<Either<Failure, Unit>> call(PenaltyEntity penalty) async {
    return await repository.updatePenalty(penalty);
  }
}
