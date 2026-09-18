import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_rule_entity.dart';

class PenaltyRuleModel extends PenaltyRuleEntity {
  const PenaltyRuleModel({
    required super.id,
    required super.title,
    required super.defaultFine,
    super.repeatedFine,
    super.isConfidential = false,
    super.category = ViolationCategory.protocolBreach,
    required super.createdAt,
    required super.updatedAt,
    super.createdBy,
  });

  factory PenaltyRuleModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PenaltyRuleModel(
      id: doc.id,
      title: data['title'] ?? '',
      defaultFine: (data['defaultFine'] as num?)?.toDouble() ?? 0.0,
      repeatedFine: (data['repeatedFine'] as num?)?.toDouble(),
      isConfidential: data['isConfidential'] ?? false,
      category: ViolationCategory.fromString(data['category'] ?? ''),
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
      createdBy: data['createdBy'],
    );
  }

  factory PenaltyRuleModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PenaltyRuleModel(
      id: id,
      title: map['title'] ?? '',
      defaultFine: (map['defaultFine'] as num?)?.toDouble() ?? 0.0,
      repeatedFine: (map['repeatedFine'] as num?)?.toDouble(),
      isConfidential: map['isConfidential'] ?? false,
      category: ViolationCategory.fromString(map['category'] ?? ''),
      createdAt: parseTimestamp(map['createdAt']),
      updatedAt: parseTimestamp(map['updatedAt']),
      createdBy: map['createdBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'defaultFine': defaultFine,
      if (repeatedFine != null) 'repeatedFine': repeatedFine,
      'isConfidential': isConfidential,
      'category': category.toFirestoreString(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (createdBy != null) 'createdBy': createdBy,
    };
  }

  factory PenaltyRuleModel.fromEntity(PenaltyRuleEntity entity) {
    return PenaltyRuleModel(
      id: entity.id,
      title: entity.title,
      defaultFine: entity.defaultFine,
      repeatedFine: entity.repeatedFine,
      isConfidential: entity.isConfidential,
      category: entity.category,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      createdBy: entity.createdBy,
    );
  }
}
