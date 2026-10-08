import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class ReviewAuditParams {
  final String organizationUID;
  final String auditId;
  final PrivateLabelReviewStatus status;
  final String reviewerUid;
  final String reviewerName;
  final String? notes;

  const ReviewAuditParams({
    required this.organizationUID,
    required this.auditId,
    required this.status,
    required this.reviewerUid,
    required this.reviewerName,
    this.notes,
  });
}

class ReviewPrivateLabelAudit
    implements UseCase<PrivateLabelAudit, ReviewAuditParams> {
  final PrivateLabelRepository repository;

  ReviewPrivateLabelAudit(this.repository);

  @override
  Future<Either<Failure, PrivateLabelAudit>> call(ReviewAuditParams params) {
    if (params.status == PrivateLabelReviewStatus.rejected &&
        (params.notes == null || params.notes!.trim().isEmpty)) {
      return Future.value(
        const Left(ServerFailure('اكتب سبب الرفض علشان المسوق يعرف يصلّح.')),
      );
    }
    return repository.reviewAudit(
      organizationUID: params.organizationUID,
      auditId: params.auditId,
      status: params.status,
      reviewerUid: params.reviewerUid,
      reviewerName: params.reviewerName,
      notes: params.notes,
    );
  }
}
