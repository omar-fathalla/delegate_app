import 'package:equatable/equatable.dart';

/// The type of update.
enum UpdateType { feature, fix, improvement }

/// The priority level of an update.
enum UpdatePriority { normal, important, critical }

/// Domain entity representing a single app update entry.
class AppUpdate extends Equatable {
  final String id;
  final String title;
  final String titleEn;
  final String description;
  final String descriptionEn;
  final String version;
  final UpdateType type;
  final UpdatePriority priority;
  final DateTime createdAt;
  final bool isActive;
  final List<String> highlights;
  final List<String> highlightsEn;

  const AppUpdate({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.description,
    required this.descriptionEn,
    required this.version,
    required this.type,
    required this.priority,
    required this.createdAt,
    required this.isActive,
    this.highlights = const [],
    this.highlightsEn = const [],
  });

  @override
  List<Object?> get props => [
    id,
    title,
    titleEn,
    description,
    descriptionEn,
    version,
    type,
    priority,
    createdAt,
    isActive,
    highlights,
    highlightsEn,
  ];
}
