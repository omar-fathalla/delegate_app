import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';

class CreatePenaltyUseCase {
  final PenaltyRepository repository;

  CreatePenaltyUseCase(this.repository);

  Future<Either<Failure, Unit>> call(PenaltyEntity penalty) async {
    return await repository.createPenalty(penalty);
  }
}
