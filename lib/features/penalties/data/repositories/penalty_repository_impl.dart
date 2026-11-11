import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/data/datasources/penalty_remote_data_source.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_rule_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_rule_entity.dart';

class PenaltyRepositoryImpl implements PenaltyRepository {
  final PenaltyRemoteDataSource remoteDataSource;

  PenaltyRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, Unit>> createPenalty(PenaltyEntity penalty) async {
    try {
      final model = PenaltyModel.fromEntity(penalty);
      await remoteDataSource.createPenalty(model);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع عند تسجيل المخالفة.'));
    }
  }

  @override
  Future<Either<Failure, List<PenaltyEntity>>> getCompanyPenalties(
    String companyId, {
    String? organizationId,
  }) async {
    try {
      final list = await remoteDataSource.getCompanyPenalties(companyId, organizationId: organizationId);
      return Right(list);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء جلب غرامات الشركة.'));
    }
  }

  @override
  Future<Either<Failure, List<PenaltyEntity>>> getDelegatePenalties({
    required String delegateId,
    String? companyId,
    String? phoneNumber,
    String? fullName,
  }) async {
    try {
      final list = await remoteDataSource.getDelegatePenalties(
        delegateId: delegateId,
        companyId: companyId,
        phoneNumber: phoneNumber,
        fullName: fullName,
      );
      return Right(list);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء جلب مخالفات المندوب.'));
    }
  }

  @override
  Future<Either<Failure, List<PenaltyEntity>>> getAllPenalties() async {
    try {
      final list = await remoteDataSource.getAllPenalties();
      return Right(list);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء جلب الغرامات.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updatePenaltyStatus({
    required String penaltyId,
    required PenaltyStatus status,
    String? rejectionReason,
    String? reviewerName,
  }) async {
    try {
      await remoteDataSource.updatePenaltyStatus(
        penaltyId: penaltyId,
        status: status,
        rejectionReason: rejectionReason,
        reviewerName: reviewerName,
      );
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء تحديث حالة المخالفة.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deletePenalty(String penaltyId) async {
    try {
      await remoteDataSource.deletePenalty(penaltyId);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء حذف المخالفة.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updatePenalty(PenaltyEntity penalty) async {
    try {
      final model = PenaltyModel.fromEntity(penalty);
      await remoteDataSource.updatePenalty(model);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع عند تعديل المخالفة.'));
    }
  }

  @override
  Future<Either<Failure, EvidenceFile>> uploadEvidenceFile({
    required File file,
    required String penaltyId,
    required String companyId,
  }) async {
    try {
      final evidence = await remoteDataSource.uploadEvidenceFile(
        file: file,
        penaltyId: penaltyId,
        companyId: companyId,
      );
      return Right(evidence);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ عند رفع مستند الإثبات.'));
    }
  }

  @override
  Future<Either<Failure, List<PenaltyRuleEntity>>> getPenaltyRules() async {
    try {
      final list = await remoteDataSource.getPenaltyRules();
      return Right(list);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء جلب إعدادات وبنود الغرامات.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> savePenaltyRule(PenaltyRuleEntity rule) async {
    try {
      final model = PenaltyRuleModel.fromEntity(rule);
      await remoteDataSource.savePenaltyRule(model);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء حفظ بند الغرامة.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updatePenaltyRuleConfidentiality(
    String ruleId,
    bool isConfidential,
  ) async {
    try {
      await remoteDataSource.updatePenaltyRuleConfidentiality(ruleId, isConfidential);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء تعديل سرية الغرامة.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deletePenaltyRule(String ruleId) async {
    try {
      await remoteDataSource.deletePenaltyRule(ruleId);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء حذف بند الغرامة.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> seedDefaultPenaltyRules() async {
    try {
      await remoteDataSource.seedDefaultPenaltyRules();
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء استيراد اللائحة الافتراضية.'));
    }
  }
}

