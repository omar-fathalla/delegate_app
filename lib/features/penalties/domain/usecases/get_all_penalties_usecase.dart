import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';

class GetAllPenaltiesUseCase {
  final PenaltyRepository repository;

  GetAllPenaltiesUseCase(this.repository);

  Future<Either<Failure, List<PenaltyEntity>>> call() async {
    return await repository.getAllPenalties();
  }
}
