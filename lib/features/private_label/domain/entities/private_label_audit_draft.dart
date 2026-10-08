import 'package:equatable/equatable.dart';

import 'private_label_audit.dart';
import 'private_label_dates.dart';

/// A captured audit that lives on the device until it is uploaded.
///
/// Image paths point to persistent local copies (App Documents directory on
/// mobile) so they survive cache cleanup while the device is offline.
class PrivateLabelAuditDraft extends Equatable {
  /// Pre-generated Firestore document ID (makes the sync idempotent).
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
  final String productImagePath;
  final String priceImagePath;
  final DateTime capturedAt;

  const PrivateLabelAuditDraft({
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
    required this.productImagePath,
    required this.priceImagePath,
    required this.capturedAt,
  });

  String get auditDate => PrivateLabelDates.dayKey(capturedAt);

  String get auditMonth => PrivateLabelDates.monthKeyOfDay(auditDate);

  bool get hasPriceMismatch =>
      referencePrice != null &&
      (shelfPrice - referencePrice!).abs() > PrivateLabelAudit.priceTolerance;

  PrivateLabelAuditDraft copyWith({
    String? productImagePath,
    String? priceImagePath,
  }) {
    return PrivateLabelAuditDraft(
      id: id,
      organizationUID: organizationUID,
      companyUID: companyUID,
      delegateUid: delegateUid,
      delegateName: delegateName,
      branchName: branchName,
      productId: productId,
      productName: productName,
      barcode: barcode,
      referencePrice: referencePrice,
      shelfPrice: shelfPrice,
      stockStatus: stockStatus,
      notes: notes,
      productImagePath: productImagePath ?? this.productImagePath,
      priceImagePath: priceImagePath ?? this.priceImagePath,
      capturedAt: capturedAt,
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
        productImagePath,
        priceImagePath,
        capturedAt,
      ];
}
