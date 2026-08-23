import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

abstract class PenaltyRepository {
  Future<Either<Failure, Unit>> createPenalty(PenaltyEntity penalty);
  Future<Either<Failure, List<PenaltyEntity>>> getCompanyPenalties(String companyId);
  Future<Either<Failure, List<PenaltyEntity>>> getAllPenalties();
  Future<Either<Failure, Unit>> updatePenaltyStatus(String penaltyId, PenaltyStatus status);
  Future<Either<Failure, Unit>> deletePenalty(String penaltyId);
  Future<Either<Failure, EvidenceFile>> uploadEvidenceFile({
    required File file,
    required String penaltyId,
  });
}
