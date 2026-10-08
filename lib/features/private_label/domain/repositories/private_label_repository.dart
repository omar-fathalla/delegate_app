import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_month_data.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';

/// Result of submitting an audit: it is always saved locally first, then
/// [synced] tells whether it already reached the server.
class PrivateLabelSubmitResult {
  final PrivateLabelAuditDraft draft;
  final bool synced;

  const PrivateLabelSubmitResult({required this.draft, required this.synced});
}

abstract class PrivateLabelRepository {
  /// Cache-first: instant month data from local storage (may be null if never cached).
  Future<Either<Failure, PrivateLabelMonthData?>> getCachedMonth({
    required String organizationUID,
    required String delegateUid,
    required int year,
    required int month,
  });

  /// Fresh month data from the server (also refreshes the local cache).
  Future<Either<Failure, PrivateLabelMonthData>> getMonth({
    required String organizationUID,
    required String delegateUid,
    required int year,
    required int month,
  });

  Future<Either<Failure, List<PrivateLabelDay>>> getOrganizationMonthDays({
    required String organizationUID,
    required String monthKey,
    String? companyUID,
  });

  Future<Either<Failure, int>> getRestAllowance(String organizationUID);

  /// Saves the draft locally (offline-first), then tries to upload it.
  Future<Either<Failure, PrivateLabelSubmitResult>> submitAudit(
    PrivateLabelAuditDraft draft,
  );

  /// Uploads every queued draft of [delegateUid]. Returns the number synced.
  Future<Either<Failure, int>> syncPendingAudits(String delegateUid);

  Future<Either<Failure, List<PrivateLabelAuditDraft>>> getPendingAudits(
    String delegateUid,
  );

  Future<Either<Failure, PrivateLabelDay>> registerRestDay({
    required String organizationUID,
    required String companyUID,
    required String delegateUid,
    required String delegateName,
    required String date,
    required int restAllowance,
  });

  Future<Either<Failure, Unit>> cancelRestDay({
    required String organizationUID,
    required String delegateUid,
    required String date,
  });

  /// Audits of a given day. [delegateUid] narrows to one marketer;
  /// a non-empty [companyUID] enforces company isolation.
  Future<Either<Failure, List<PrivateLabelAudit>>> getAudits({
    required String organizationUID,
    String? date,
    String? delegateUid,
    String? companyUID,
  });

  Future<Either<Failure, PrivateLabelAudit>> reviewAudit({
    required String organizationUID,
    required String auditId,
    required PrivateLabelReviewStatus status,
    required String reviewerUid,
    required String reviewerName,
    String? notes,
  });

  Future<Either<Failure, List<PrivateLabelProduct>>> getProducts(
    String organizationUID,
  );

  Future<Either<Failure, PrivateLabelProduct>> saveProduct(
    PrivateLabelProduct product,
  );

  Future<Either<Failure, Unit>> deleteAudit({
    required String organizationUID,
    required String auditId,
    required String delegateUid,
    required String date,
  });

  Future<Either<Failure, PrivateLabelAudit>> updateAudit({
    required String organizationUID,
    required String auditId,
    required String productName,
    String? productId,
    double? referencePrice,
    required double shelfPrice,
    required PrivateLabelStockStatus stockStatus,
    String? barcode,
    String? notes,
  });

  Future<Either<Failure, List<String>>> getBranches(String organizationUID);
}
