import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';

/// Firestore-compatible data model for app updates.
class AppUpdateModel extends AppUpdate {
  const AppUpdateModel({
    required super.id,
    required super.title,
    required super.titleEn,
    required super.description,
    required super.descriptionEn,
    required super.version,
    required super.type,
    required super.priority,
    required super.createdAt,
    required super.isActive,
    super.highlights,
    super.highlightsEn,
  });

  factory AppUpdateModel.fromJson(Map<String, dynamic> json, String id) {
    return AppUpdateModel(
      id: id,
      title: json['title'] ?? '',
      titleEn: json['titleEn'] ?? '',
      description: json['description'] ?? '',
      descriptionEn: json['descriptionEn'] ?? '',
      version: json['version'] ?? '',
      type: _parseUpdateType(json['type']),
      priority: _parseUpdatePriority(json['priority']),
      createdAt: _parseTimestamp(json['createdAt']),
      isActive: json['isActive'] ?? true,
      highlights: _parseStringList(json['highlights']),
      highlightsEn: _parseStringList(json['highlightsEn']),
    );
  }

  static UpdateType _parseUpdateType(dynamic value) {
    switch (value?.toString()) {
      case 'feature':
        return UpdateType.feature;
      case 'fix':
        return UpdateType.fix;
      case 'improvement':
        return UpdateType.improvement;
      default:
        return UpdateType.feature;
    }
  }

  static UpdatePriority _parseUpdatePriority(dynamic value) {
    switch (value?.toString()) {
      case 'important':
        return UpdatePriority.important;
      case 'critical':
        return UpdatePriority.critical;
      default:
        return UpdatePriority.normal;
    }
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }
}
