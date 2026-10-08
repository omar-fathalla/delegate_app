import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class SubmitPrivateLabelAudit
    implements UseCase<PrivateLabelSubmitResult, PrivateLabelAuditDraft> {
  final PrivateLabelRepository repository;

  SubmitPrivateLabelAudit(this.repository);

  @override
  Future<Either<Failure, PrivateLabelSubmitResult>> call(
    PrivateLabelAuditDraft params,
  ) {
    if (params.productName.trim().isEmpty) {
      return Future.value(const Left(ServerFailure('اكتب اسم المنتج.')));
    }
    if (params.branchName.trim().isEmpty) {
      return Future.value(const Left(ServerFailure('اختار الفرع الأول.')));
    }
    if (params.shelfPrice <= 0) {
      return Future.value(const Left(ServerFailure('اكتب سعر الرف بشكل صحيح.')));
    }
    if (params.productImagePath.isEmpty || params.priceImagePath.isEmpty) {
      return Future.value(
        const Left(ServerFailure('لازم صورة المنتج وصورة بطاقة السعر.')),
      );
    }
    return repository.submitAudit(params);
  }
}
