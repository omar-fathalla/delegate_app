import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_json.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';

/// Firestore: `/organizations/{organizationUID}/private_label_audits/{id}`
class PrivateLabelAuditModel extends PrivateLabelAudit {
  const PrivateLabelAuditModel({
    required super.id,
    required super.organizationUID,
    required super.companyUID,
    required super.delegateUid,
    required super.delegateName,
    required super.branchName,
    super.productId,
    required super.productName,
    super.barcode,
    super.referencePrice,
    required super.shelfPrice,
    required super.stockStatus,
    super.notes,
    required super.productPhotoUrl,
    required super.pricePhotoUrl,
    super.reviewStatus,
    super.reviewedBy,
    super.reviewedByName,
    super.reviewNotes,
    super.reviewedAt,
    required super.auditDate,
    required super.auditMonth,
    required super.capturedAt,
    super.syncedAt,
  });

  factory PrivateLabelAuditModel.fromJson(Map<String, dynamic> json, String id) {
    final capturedAt = PrivateLabelJson.parseDate(json['capturedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return PrivateLabelAuditModel(
      id: id,
      organizationUID: PrivateLabelJson.parseString(json['organizationUID']),
      companyUID: PrivateLabelJson.parseString(json['companyUID']),
      delegateUid: PrivateLabelJson.parseString(json['delegateUid']),
      delegateName: PrivateLabelJson.parseString(json['delegateName']),
      branchName: PrivateLabelJson.parseString(json['branchName']),
      productId: PrivateLabelJson.parseNullableString(json['productId']),
      productName: PrivateLabelJson.parseString(json['productName']),
      barcode: PrivateLabelJson.parseNullableString(json['barcode']),
      referencePrice: PrivateLabelJson.parseDouble(json['referencePrice']),
      shelfPrice: PrivateLabelJson.parseDouble(json['shelfPrice']) ?? 0,
      stockStatus: privateLabelStockStatusFromString(json['stockStatus'] as String?),
      notes: PrivateLabelJson.parseNullableString(json['notes']),
      productPhotoUrl: PrivateLabelJson.parseString(json['productPhotoUrl']),
      pricePhotoUrl: PrivateLabelJson.parseString(json['pricePhotoUrl']),
      reviewStatus:
          privateLabelReviewStatusFromString(json['reviewStatus'] as String?),
      reviewedBy: PrivateLabelJson.parseNullableString(json['reviewedBy']),
      reviewedByName: PrivateLabelJson.parseNullableString(json['reviewedByName']),
      reviewNotes: PrivateLabelJson.parseNullableString(json['reviewNotes']),
      reviewedAt: PrivateLabelJson.parseDate(json['reviewedAt']),
      auditDate: PrivateLabelJson.parseString(json['auditDate']),
      auditMonth: PrivateLabelJson.parseString(json['auditMonth']),
      capturedAt: capturedAt,
      syncedAt: PrivateLabelJson.parseDate(json['syncedAt']),
    );
  }

  /// Builds the server document from a local draft + uploaded photo URLs.
  static Map<String, dynamic> firestoreFromDraft(
    PrivateLabelAuditDraft draft, {
    required String productPhotoUrl,
    required String pricePhotoUrl,
  }) {
    return {
      'id': draft.id,
      'organizationUID': draft.organizationUID,
      'companyUID': draft.companyUID,
      'delegateUid': draft.delegateUid,
      'delegateName': draft.delegateName,
      'branchName': draft.branchName,
      'productId': draft.productId,
      'productName': draft.productName.trim(),
      'barcode': draft.barcode,
      'referencePrice': draft.referencePrice,
      'shelfPrice': draft.shelfPrice,
      'priceMismatch': draft.hasPriceMismatch,
      'stockStatus': draft.stockStatus.name,
      'notes': draft.notes,
      'productPhotoUrl': productPhotoUrl,
      'pricePhotoUrl': pricePhotoUrl,
      'reviewStatus': PrivateLabelReviewStatus.pending.name,
      'auditDate': draft.auditDate,
      'auditMonth': draft.auditMonth,
      'capturedAt': Timestamp.fromDate(draft.capturedAt),
      'syncedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

/// Local (SharedPreferences) JSON for the offline queue.
abstract final class PrivateLabelAuditDraftJson {
  static Map<String, dynamic> toJson(PrivateLabelAuditDraft d) => {
        'id': d.id,
        'organizationUID': d.organizationUID,
        'companyUID': d.companyUID,
        'delegateUid': d.delegateUid,
        'delegateName': d.delegateName,
        'branchName': d.branchName,
        'productId': d.productId,
        'productName': d.productName,
        'barcode': d.barcode,
        'referencePrice': d.referencePrice,
        'shelfPrice': d.shelfPrice,
        'stockStatus': d.stockStatus.name,
        'notes': d.notes,
        'productImagePath': d.productImagePath,
        'priceImagePath': d.priceImagePath,
        'capturedAt': d.capturedAt.toIso8601String(),
      };

  static PrivateLabelAuditDraft fromJson(Map<String, dynamic> json) {
    return PrivateLabelAuditDraft(
      id: PrivateLabelJson.parseString(json['id']),
      organizationUID: PrivateLabelJson.parseString(json['organizationUID']),
      companyUID: PrivateLabelJson.parseString(json['companyUID']),
      delegateUid: PrivateLabelJson.parseString(json['delegateUid']),
      delegateName: PrivateLabelJson.parseString(json['delegateName']),
      branchName: PrivateLabelJson.parseString(json['branchName']),
      productId: PrivateLabelJson.parseNullableString(json['productId']),
      productName: PrivateLabelJson.parseString(json['productName']),
      barcode: PrivateLabelJson.parseNullableString(json['barcode']),
      referencePrice: PrivateLabelJson.parseDouble(json['referencePrice']),
      shelfPrice: PrivateLabelJson.parseDouble(json['shelfPrice']) ?? 0,
      stockStatus: privateLabelStockStatusFromString(json['stockStatus'] as String?),
      notes: PrivateLabelJson.parseNullableString(json['notes']),
      productImagePath: PrivateLabelJson.parseString(json['productImagePath']),
      priceImagePath: PrivateLabelJson.parseString(json['priceImagePath']),
      capturedAt: PrivateLabelJson.parseDate(json['capturedAt']) ?? DateTime.now(),
    );
  }
}
