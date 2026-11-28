import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

import 'package:delegate_app/features/penalties/domain/entities/penalty_rule_entity.dart';

abstract class PenaltyRepository {
  Future<Either<Failure, Unit>> createPenalty(PenaltyEntity penalty);
  Future<Either<Failure, List<PenaltyEntity>>> getCompanyPenalties(String companyId, {String? organizationId});
  Future<Either<Failure, List<PenaltyEntity>>> getDelegatePenalties({
    required String delegateId,
    String? companyId,
    String? phoneNumber,
    String? fullName,
  });
  Future<Either<Failure, List<PenaltyEntity>>> getOwnPenalties({
    required String uid,
    required String companyId,
    String? phoneNumber,
  });
  Future<Either<Failure, List<PenaltyEntity>>> getAllPenalties();
  Future<Either<Failure, Unit>> updatePenaltyStatus({
    required String penaltyId,
    required PenaltyStatus status,
    String? rejectionReason,
    String? reviewerName,
  });
  Future<Either<Failure, Unit>> deletePenalty(String penaltyId);

  /// TAS-365: acknowledge / dispute (delegate) or resolve (super admin,
  /// chain admin) through the respondToPenalty callable. Right: new status.
  Future<Either<Failure, String>> respondToPenalty({
    required String penaltyId,
    required String action,
    String? reason,
    String? decision,
  });
  Future<Either<Failure, Unit>> updatePenalty(PenaltyEntity penalty);
  Future<Either<Failure, EvidenceFile>> uploadEvidenceFile({
    required File file,
    required String penaltyId,
    required String companyId,
  });
  Future<Either<Failure, List<PenaltyRuleEntity>>> getPenaltyRules();
  Future<Either<Failure, Unit>> savePenaltyRule(PenaltyRuleEntity rule);
  Future<Either<Failure, Unit>> updatePenaltyRuleConfidentiality(String ruleId, bool isConfidential);
  Future<Either<Failure, Unit>> deletePenaltyRule(String ruleId);
  Future<Either<Failure, Unit>> seedDefaultPenaltyRules();
}

