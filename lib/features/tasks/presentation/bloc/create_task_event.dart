import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class CreateTaskEvent extends Equatable {
  const CreateTaskEvent();

  @override
  List<Object?> get props => [];
}

class CreateTaskSubmitted extends CreateTaskEvent {
  final String organizationId;
  final String title;
  final String description;
  final TaskPriority priority;
  final DateTime dueDate;
  final String assignedTo; // UID or 'all'
  final String assignedToName;
  final String companyId;
  final String createdBy;
  final String createdByName;
  final String? imageUrl;
  final String? imagePath;

  const CreateTaskSubmitted({
    required this.organizationId,
    required this.title,
    required this.description,
    required this.priority,
    required this.dueDate,
    required this.assignedTo,
    required this.assignedToName,
    required this.companyId,
    required this.createdBy,
    required this.createdByName,
    this.imageUrl,
    this.imagePath,
  });

  @override
  List<Object?> get props => [
    organizationId,
    title,
    description,
    priority,
    dueDate,
    assignedTo,
    assignedToName,
    companyId,
    createdBy,
    createdByName,
    imageUrl,
    imagePath,
  ];
}

class LoadDelegatesRequested extends CreateTaskEvent {
  final String organizationId;
  final String companyId;

  const LoadDelegatesRequested({
    required this.organizationId,
    required this.companyId,
  });

  @override
  List<Object?> get props => [organizationId, companyId];
}
