import 'package:equatable/equatable.dart';

/// Shelf availability of the audited product.
enum PrivateLabelStockStatus { available, low, outOfStock, notDisplayed }

/// Review decision taken by Marketing Promotion (audit).
///
/// - [priceIssue]: documentation is valid, but the shelf price is wrong and the
///   branch must fix it. This does NOT count against the marketer's KPI.
/// - [rejected]: the documentation itself is invalid (unclear / wrong photo).
///   A day whose audits are all rejected is not counted as achieved.
enum PrivateLabelReviewStatus { pending, approved, priceIssue, rejected }

PrivateLabelStockStatus privateLabelStockStatusFromString(String? value) {
  return PrivateLabelStockStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PrivateLabelStockStatus.available,
  );
}

PrivateLabelReviewStatus privateLabelReviewStatusFromString(String? value) {
  return PrivateLabelReviewStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PrivateLabelReviewStatus.pending,
  );
}

/// A single documented product on a branch shelf (product photo + price tag photo).
class PrivateLabelAudit extends Equatable {
  /// Tolerance used to compare shelf price vs. reference price.
  static const double priceTolerance = 0.009;

  final String id;
  final String organizationUID;
  final String companyUID;
  final String delegateUid;
  final String delegateName;
  final String branchName;
  final String? productId;
  final String productName;
  final String? barcode;
  final double? referencePrice;
  final double shelfPrice;
  final PrivateLabelStockStatus stockStatus;
  final String? notes;
  final String productPhotoUrl;
  final String pricePhotoUrl;
  final PrivateLabelReviewStatus reviewStatus;
  final String? reviewedBy;
  final String? reviewedByName;
  final String? reviewNotes;
  final DateTime? reviewedAt;

  /// `yyyy-MM-dd` (device date at capture time).
  final String auditDate;

  /// `yyyy-MM`
  final String auditMonth;

  /// Device time at capture.
  final DateTime capturedAt;

  /// Server time at sync (null until the server acknowledges the write).
  final DateTime? syncedAt;

  const PrivateLabelAudit({
    required this.id,
    required this.organizationUID,
    required this.companyUID,
    required this.delegateUid,
    required this.delegateName,
    required this.branchName,
    this.productId,
    required this.productName,
    this.barcode,
    this.referencePrice,
    required this.shelfPrice,
    required this.stockStatus,
    this.notes,
    required this.productPhotoUrl,
    required this.pricePhotoUrl,
    this.reviewStatus = PrivateLabelReviewStatus.pending,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewNotes,
    this.reviewedAt,
    required this.auditDate,
    required this.auditMonth,
    required this.capturedAt,
    this.syncedAt,
  });

  /// True when a reference price exists and the shelf price differs from it.
  bool get hasPriceMismatch =>
      referencePrice != null &&
      (shelfPrice - referencePrice!).abs() > priceTolerance;

  /// Anti-fraud hint: captured offline and synced 24h+ later (or device clock skew).
  bool get hasClockSkewWarning =>
      syncedAt != null && syncedAt!.difference(capturedAt).inHours.abs() >= 24;

  PrivateLabelAudit copyWith({
    String? productName,
    String? productId,
    String? barcode,
    double? referencePrice,
    double? shelfPrice,
    PrivateLabelStockStatus? stockStatus,
    String? notes,
    PrivateLabelReviewStatus? reviewStatus,
    String? reviewedBy,
    String? reviewedByName,
    String? reviewNotes,
    DateTime? reviewedAt,
  }) {
    return PrivateLabelAudit(
      id: id,
      organizationUID: organizationUID,
      companyUID: companyUID,
      delegateUid: delegateUid,
      delegateName: delegateName,
      branchName: branchName,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      barcode: barcode ?? this.barcode,
      referencePrice: referencePrice ?? this.referencePrice,
      shelfPrice: shelfPrice ?? this.shelfPrice,
      stockStatus: stockStatus ?? this.stockStatus,
      notes: notes ?? this.notes,
      productPhotoUrl: productPhotoUrl,
      pricePhotoUrl: pricePhotoUrl,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedByName: reviewedByName ?? this.reviewedByName,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      auditDate: auditDate,
      auditMonth: auditMonth,
      capturedAt: capturedAt,
      syncedAt: syncedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        organizationUID,
        companyUID,
        delegateUid,
        delegateName,
        branchName,
        productId,
        productName,
        barcode,
        referencePrice,
        shelfPrice,
        stockStatus,
        notes,
        productPhotoUrl,
        pricePhotoUrl,
        reviewStatus,
        reviewedBy,
        reviewedByName,
        reviewNotes,
        reviewedAt,
        auditDate,
        auditMonth,
        capturedAt,
        syncedAt,
      ];
}
