import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

class PenaltyModel extends PenaltyEntity {
  const PenaltyModel({
    required super.penaltyId,
    required super.companyId,
    required super.companyName,
    super.branchId,
    super.branchName,
    required super.createdById,
    required super.createdByName,
    super.createdByPhone,
    required super.title,
    required super.category,
    required super.incidentDescription,
    required super.fineAmount,
    super.currency = 'EGP',
    super.status = PenaltyStatus.pendingBranchesMarketing,
    super.evidenceFiles = const [],
    super.branchesMarketingApprovedBy,
    super.branchesMarketingApprovedAt,
    super.generalManagerApprovedBy,
    super.generalManagerApprovedAt,
    super.rejectionReason,
    super.targetDelegateId,
    super.targetDelegateName,
    super.isRepeated = false,
    super.isConfidential = false,
    required super.createdAt,
    required super.updatedAt,
  });

  factory PenaltyModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullableTimestamp(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawFiles = data['evidenceFiles'] as List<dynamic>? ?? [];
    final evidenceFilesList = rawFiles
        .map((f) => EvidenceFile.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();

    return PenaltyModel(
      penaltyId: data['penaltyId'] ?? doc.id,
      companyId: data['companyId'] ?? '',
      companyName: data['companyName'] ?? '',
      branchId: data['branchId'],
      branchName: data['branchName'],
      createdById: data['createdById'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdByPhone: data['createdByPhone']?.toString() ??
          data['creatorPhone']?.toString() ??
          data['phone']?.toString(),
      title: data['title'] ?? '',
      category: ViolationCategory.fromString(data['category'] ?? ''),
      incidentDescription: data['incidentDescription'] ?? '',
      fineAmount: (data['fineAmount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'EGP',
      status: PenaltyStatus.fromString(data['status'] ?? ''),
      evidenceFiles: evidenceFilesList,
      branchesMarketingApprovedBy: data['branchesMarketingApprovedBy'],
      branchesMarketingApprovedAt: parseNullableTimestamp(data['branchesMarketingApprovedAt']),
      generalManagerApprovedBy: data['generalManagerApprovedBy'],
      generalManagerApprovedAt: parseNullableTimestamp(data['generalManagerApprovedAt']),
      rejectionReason: data['rejectionReason'],
      targetDelegateId: data['targetDelegateId'],
      targetDelegateName: data['targetDelegateName'],
      isRepeated: data['isRepeated'] ?? false,
      isConfidential: data['isConfidential'] ?? false,
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'penaltyId': penaltyId,
      'companyId': companyId,
      'companyName': companyName,
      if (branchId != null) 'branchId': branchId,
      if (branchName != null) 'branchName': branchName,
      'createdById': createdById,
      'createdByName': createdByName,
      if (createdByPhone != null) 'createdByPhone': createdByPhone,
      'title': title,
      'category': category.toFirestoreString(),
      'incidentDescription': incidentDescription,
      'fineAmount': fineAmount,
      'currency': currency,
      'status': status.toFirestoreString(),
      'evidenceFiles': evidenceFiles.map((e) => e.toJson()).toList(),
      if (branchesMarketingApprovedBy != null)
        'branchesMarketingApprovedBy': branchesMarketingApprovedBy,
      if (branchesMarketingApprovedAt != null)
        'branchesMarketingApprovedAt': Timestamp.fromDate(branchesMarketingApprovedAt!),
      if (generalManagerApprovedBy != null)
        'generalManagerApprovedBy': generalManagerApprovedBy,
      if (generalManagerApprovedAt != null)
        'generalManagerApprovedAt': Timestamp.fromDate(generalManagerApprovedAt!),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (targetDelegateId != null) 'targetDelegateId': targetDelegateId,
      if (targetDelegateName != null) 'targetDelegateName': targetDelegateName,
      'isRepeated': isRepeated,
      'isConfidential': isConfidential,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory PenaltyModel.fromEntity(PenaltyEntity entity) {
    return PenaltyModel(
      penaltyId: entity.penaltyId,
      companyId: entity.companyId,
      companyName: entity.companyName,
      branchId: entity.branchId,
      branchName: entity.branchName,
      createdById: entity.createdById,
      createdByName: entity.createdByName,
      createdByPhone: entity.createdByPhone,
      title: entity.title,
      category: entity.category,
      incidentDescription: entity.incidentDescription,
      fineAmount: entity.fineAmount,
      currency: entity.currency,
      status: entity.status,
      evidenceFiles: entity.evidenceFiles,
      branchesMarketingApprovedBy: entity.branchesMarketingApprovedBy,
      branchesMarketingApprovedAt: entity.branchesMarketingApprovedAt,
      generalManagerApprovedBy: entity.generalManagerApprovedBy,
      generalManagerApprovedAt: entity.generalManagerApprovedAt,
      rejectionReason: entity.rejectionReason,
      targetDelegateId: entity.targetDelegateId,
      targetDelegateName: entity.targetDelegateName,
      isRepeated: entity.isRepeated,
      isConfidential: entity.isConfidential,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
