import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';

class PenaltyRuleEntity extends Equatable {
  final String id;
  final String title;
  final double defaultFine;
  final double? repeatedFine;
  final bool isConfidential;
  final ViolationCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  const PenaltyRuleEntity({
    required this.id,
    required this.title,
    required this.defaultFine,
    this.repeatedFine,
    this.isConfidential = false,
    this.category = ViolationCategory.protocolBreach,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  PenaltyRuleEntity copyWith({
    String? id,
    String? title,
    double? defaultFine,
    double? repeatedFine,
    bool? isConfidential,
    ViolationCategory? category,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return PenaltyRuleEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      defaultFine: defaultFine ?? this.defaultFine,
      repeatedFine: repeatedFine ?? this.repeatedFine,
      isConfidential: isConfidential ?? this.isConfidential,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        defaultFine,
        repeatedFine,
        isConfidential,
        category,
        createdAt,
        updatedAt,
        createdBy,
      ];
}
