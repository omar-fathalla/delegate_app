import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';

abstract class TaskRemoteDataSource {
  Future<TaskModel> createTask(String organizationId, TaskModel task);
  Future<void> updateTaskStatus(
    String organizationId,
    String taskId,
    TaskStatus status, {
    String? notes,
    String? completedBy,
  });
  Future<List<TaskModel>> getAdminTasks(
    String organizationId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  });
  Future<List<TaskModel>> getDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  });
  Future<void> updateTask(String organizationId, TaskModel task);

  Future<void> deleteTask(String organizationId, String taskId);
}

class TaskRemoteDataSourceImpl implements TaskRemoteDataSource {
  final FirebaseFirestore firestore;

  TaskRemoteDataSourceImpl({required this.firestore});

  CollectionReference _taskCollection(String organizationId) => firestore
      .collection('organizations')
      .doc(organizationId)
      .collection('tasks');

  @override
  Future<TaskModel> createTask(String organizationId, TaskModel task) async {
    final docRef = _taskCollection(organizationId).doc();
    final taskWithId = TaskModel(
      uid: docRef.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      status: task.status,
      assignedTo: task.assignedTo,
      assignedToName: task.assignedToName,
      companyId: task.companyId,
      createdBy: task.createdBy,
      createdByName: task.createdByName,
      dueDate: task.dueDate,
      createdAt: task.createdAt,
    );
    await docRef.set(taskWithId.toFirestore());
    return taskWithId;
  }

  @override
  Future<void> updateTaskStatus(
    String organizationId,
    String taskId,
    TaskStatus status, {
    String? notes,
    String? completedBy,
  }) async {
    final updates = <String, dynamic>{'status': status.name};
    if (status == TaskStatus.completed) {
      updates['completedAt'] = FieldValue.serverTimestamp();
      if (completedBy != null) updates['completedBy'] = completedBy;
    }
    if (notes != null) updates['notes'] = notes;

    await _taskCollection(organizationId).doc(taskId).update(updates);
  }

  @override
  Future<List<TaskModel>> getAdminTasks(
    String organizationId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) async {
    Query query = _taskCollection(organizationId)
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    if (lastDoc != null && lastDoc is DocumentSnapshot) {
      query = query.startAfterDocument(lastDoc);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
  }

  @override
  Future<List<TaskModel>> getDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) async {
    Query query = _taskCollection(organizationId)
        .where('companyId', isEqualTo: companyId)
        .where(
          Filter.or(
            Filter('assignedTo', isEqualTo: delegateId),
            Filter('assignedTo', isEqualTo: 'all'),
          ),
        )
        .orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    if (lastDoc != null && lastDoc is DocumentSnapshot) {
      query = query.startAfterDocument(lastDoc);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
  }

  @override
  Future<void> updateTask(String organizationId, TaskModel task) async {
    await _taskCollection(
      organizationId,
    ).doc(task.uid).update(task.toFirestore());
  }

  @override
  Future<void> deleteTask(String organizationId, String taskId) async {
    await _taskCollection(organizationId).doc(taskId).delete();
  }
}
