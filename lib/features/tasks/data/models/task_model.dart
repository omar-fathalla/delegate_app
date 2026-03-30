import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

class TaskModel extends TaskEntity {
  const TaskModel({
    required super.uid,
    required super.title,
    required super.description,
    required super.priority,
    required super.status,
    required super.assignedTo,
    required super.assignedToName,
    required super.companyId,
    required super.createdBy,
    required super.createdByName,
    required super.dueDate,
    required super.createdAt,
    super.completedAt,
    super.completedBy,
    super.notes,
  });

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      uid: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      priority: _priorityFromString(data['priority']),
      status: _statusFromString(data['status']),
      assignedTo: data['assignedTo'] ?? '',
      assignedToName: data['assignedToName'] ?? '',
      companyId: data['companyId'] ?? '',
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
      completedBy: data['completedBy'],
      notes: data['notes'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'priority': priority.name,
      'status': status.name,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'companyId': companyId,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'dueDate': Timestamp.fromDate(dueDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      'completedBy': completedBy,
      'notes': notes,
    };
  }

  static TaskPriority _priorityFromString(String? priority) {
    switch (priority) {
      case 'high':
        return TaskPriority.high;
      case 'medium':
        return TaskPriority.medium;
      case 'low':
      default:
        return TaskPriority.low;
    }
  }

  static TaskStatus _statusFromString(String? status) {
    switch (status) {
      case 'inProgress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      case 'pending':
      default:
        return TaskStatus.pending;
    }
  }

  factory TaskModel.fromEntity(TaskEntity entity) {
    return TaskModel(
      uid: entity.uid,
      title: entity.title,
      description: entity.description,
      priority: entity.priority,
      status: entity.status,
      assignedTo: entity.assignedTo,
      assignedToName: entity.assignedToName,
      companyId: entity.companyId,
      createdBy: entity.createdBy,
      createdByName: entity.createdByName,
      dueDate: entity.dueDate,
      createdAt: entity.createdAt,
      completedAt: entity.completedAt,
      completedBy: entity.completedBy,
      notes: entity.notes,
    );
  }
}
