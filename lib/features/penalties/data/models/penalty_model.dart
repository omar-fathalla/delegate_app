import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

class PenaltyModel extends PenaltyEntity {
  const PenaltyModel({
    required super.penaltyId,
    required super.companyId,
    required super.companyName,
    required super.createdById,
    required super.createdByName,
    required super.title,
    required super.category,
    required super.incidentDescription,
    required super.fineAmount,
    super.currency = 'EGP',
    super.status = PenaltyStatus.issued,
    super.evidenceFiles = const [],
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

    final rawFiles = data['evidenceFiles'] as List<dynamic>? ?? [];
    final evidenceFilesList = rawFiles
        .map((f) => EvidenceFile.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();

    return PenaltyModel(
      penaltyId: data['penaltyId'] ?? doc.id,
      companyId: data['companyId'] ?? '',
      companyName: data['companyName'] ?? '',
      createdById: data['createdById'] ?? '',
      createdByName: data['createdByName'] ?? '',
      title: data['title'] ?? '',
      category: ViolationCategory.fromString(data['category'] ?? ''),
      incidentDescription: data['incidentDescription'] ?? '',
      fineAmount: (data['fineAmount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'EGP',
      status: PenaltyStatus.fromString(data['status'] ?? ''),
      evidenceFiles: evidenceFilesList,
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'penaltyId': penaltyId,
      'companyId': companyId,
      'companyName': companyName,
      'createdById': createdById,
      'createdByName': createdByName,
      'title': title,
      'category': category.toFirestoreString(),
      'incidentDescription': incidentDescription,
      'fineAmount': fineAmount,
      'currency': currency,
      'status': status.toFirestoreString(),
      'evidenceFiles': evidenceFiles.map((e) => e.toJson()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory PenaltyModel.fromEntity(PenaltyEntity entity) {
    return PenaltyModel(
      penaltyId: entity.penaltyId,
      companyId: entity.companyId,
      companyName: entity.companyName,
      createdById: entity.createdById,
      createdByName: entity.createdByName,
      title: entity.title,
      category: entity.category,
      incidentDescription: entity.incidentDescription,
      fineAmount: entity.fineAmount,
      currency: entity.currency,
      status: entity.status,
      evidenceFiles: entity.evidenceFiles,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
