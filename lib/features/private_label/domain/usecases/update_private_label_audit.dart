import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class UpdateAuditParams {
  final String organizationUID;
  final String auditId;
  final String productName;
  final String? productId;
  final double? referencePrice;
  final double shelfPrice;
  final PrivateLabelStockStatus stockStatus;
  final String? barcode;
  final String? notes;

  const UpdateAuditParams({
    required this.organizationUID,
    required this.auditId,
    required this.productName,
    this.productId,
    this.referencePrice,
    required this.shelfPrice,
    required this.stockStatus,
    this.barcode,
    this.notes,
  });
}

class UpdatePrivateLabelAudit implements UseCase<PrivateLabelAudit, UpdateAuditParams> {
  final PrivateLabelRepository repository;

  UpdatePrivateLabelAudit(this.repository);

  @override
  Future<Either<Failure, PrivateLabelAudit>> call(UpdateAuditParams params) {
    if (params.productName.trim().isEmpty) {
      return Future.value(const Left(ServerFailure('اسم المنتج مطلوب.')));
    }
    if (params.shelfPrice <= 0) {
      return Future.value(const Left(ServerFailure('سعر الرف غير صحيح.')));
    }
    return repository.updateAudit(
      organizationUID: params.organizationUID,
      auditId: params.auditId,
      productName: params.productName.trim(),
      productId: params.productId,
      referencePrice: params.referencePrice,
      shelfPrice: params.shelfPrice,
      stockStatus: params.stockStatus,
      barcode: params.barcode,
      notes: params.notes,
    );
  }
}
