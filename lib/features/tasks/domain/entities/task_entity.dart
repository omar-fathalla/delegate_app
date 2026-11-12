import 'package:equatable/equatable.dart';

enum TaskPriority { high, medium, low }

enum TaskStatus { pending, inProgress, completed, cancelled }

class TaskEntity extends Equatable {
  final String uid;
  final String title;
  final String description;
  final TaskPriority priority;
  final TaskStatus status;
  final String assignedTo; // 'all' or delegate UID
  final String assignedToName;
  final String companyId;
  final String createdBy; // Admin UID
  final String createdByName;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String?
  completedBy; // If assigned to 'all', who completed it? (or just for standard tracking)
  final String? notes;

  /// Download URL of the image the sender attached, if any.
  final String? imageUrl;

  /// Storage path of the attached image. Display goes through getTaskImage.
  final String? imagePath;

  /// Set when the sender edits the title, description or image.
  final DateTime? editedAt;

  bool get hasImage =>
      (imagePath != null && imagePath!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);
  bool get isEdited => editedAt != null;

  const TaskEntity({
    required this.uid,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.assignedTo,
    required this.assignedToName,
    required this.companyId,
    required this.createdBy,
    required this.createdByName,
    required this.dueDate,
    required this.createdAt,
    this.completedAt,
    this.completedBy,
    this.notes,
    this.imageUrl,
    this.imagePath,
    this.editedAt,
  });

  TaskEntity copyWith({
    String? uid,
    String? title,
    String? description,
    TaskPriority? priority,
    TaskStatus? status,
    String? assignedTo,
    String? assignedToName,
    String? companyId,
    String? createdBy,
    String? createdByName,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? completedAt,
    String? completedBy,
    String? notes,
    String? imageUrl,
    String? imagePath,
    DateTime? editedAt,
    bool clearImage = false,
    bool clearImageUrl = false,
  }) {
    return TaskEntity(
      uid: uid ?? this.uid,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      companyId: companyId ?? this.companyId,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      notes: notes ?? this.notes,
      imageUrl: clearImage || clearImageUrl
          ? null
          : (imageUrl ?? this.imageUrl),
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      editedAt: editedAt ?? this.editedAt,
    );
  }

  @override
  List<Object?> get props => [
    uid,
    title,
    description,
    priority,
    status,
    assignedTo,
    assignedToName,
    companyId,
    createdBy,
    createdByName,
    dueDate,
    createdAt,
    completedAt,
    completedBy,
    notes,
    imageUrl,
    imagePath,
    editedAt,
  ];
}
