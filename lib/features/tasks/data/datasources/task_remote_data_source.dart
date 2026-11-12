import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/task_image_paths.dart';
import 'package:delegate_app/features/tasks/domain/task_proof_paths.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_proof.dart';

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
    String? adminId,
    String? adminRoleName,
  });
  Future<List<TaskModel>> getDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId,
    String delegateRoleName, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  });
  Stream<List<TaskModel>> streamDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId,
    String delegateRoleName,
  );
  Stream<List<TaskModel>> streamAdminTasks(
    String organizationId,
    String companyId,
  );
  Future<void> updateTask(String organizationId, TaskModel task);

  Future<void> deleteTask(String organizationId, String taskId);
  Future<TaskProof?> getTaskProof(
    String organizationId,
    String taskId,
    String uploaderUid,
  );
  Future<List<TaskProof>> listTaskProofs(String organizationId, String taskId);
  Future<void> saveTaskProof({
    required String organizationId,
    required String taskId,
    required String uploaderUid,
    required List<String> imagePaths,
    required String companyUID,
  });
}

class TaskRemoteDataSourceImpl implements TaskRemoteDataSource {
  final FirebaseFirestore firestore;
  final FirebaseStorage? _storage;

  TaskRemoteDataSourceImpl({required this.firestore, FirebaseStorage? storage})
    : _storage = storage;

  FirebaseStorage get storage => _storage ?? FirebaseStorage.instance;

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
      imageUrl: task.imageUrl,
      imagePath: task.imagePath,
      imagePaths: task.imagePaths,
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
    String? adminId,
    String? adminRoleName,
  }) async {
    Query query = _taskCollection(
      organizationId,
    ).where('companyId', isEqualTo: companyId);

    if (adminId != null &&
        adminRoleName != null &&
        adminRoleName == 'marketingPromotion') {
      query = query.where(
        Filter.or(
          Filter('createdBy', isEqualTo: adminId),
          Filter('assignedTo', isEqualTo: adminId),
          Filter('assignedTo', isEqualTo: 'all'),
          Filter('assignedTo', isEqualTo: 'all_marketing_promotion'),
        ),
      );
    }

    query = query.orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    if (lastDoc != null && lastDoc is DocumentSnapshot) {
      query = query.startAfterDocument(lastDoc);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.getResilient();
    return snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
  }

  @override
  Stream<List<TaskModel>> streamAdminTasks(
    String organizationId,
    String companyId,
  ) {
    return _taskCollection(organizationId)
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList(),
        );
  }

  @override
  Stream<List<TaskModel>> streamDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId,
    String delegateRoleName,
  ) {
    Query query = _taskCollection(
      organizationId,
    ).where('companyId', isEqualTo: companyId);

    if (delegateRoleName == 'marketing') {
      query = query.where(
        Filter.or(
          Filter('assignedTo', isEqualTo: delegateId),
          Filter('assignedTo', isEqualTo: 'all'),
          Filter('assignedTo', isEqualTo: 'all_branch_marketing'),
        ),
      );
    } else if (delegateRoleName == 'marketingPromotion') {
      query = query.where(
        Filter.or(
          Filter('assignedTo', isEqualTo: delegateId),
          Filter('assignedTo', isEqualTo: 'all'),
          Filter('assignedTo', isEqualTo: 'all_marketing_promotion'),
        ),
      );
    } else {
      query = query.where(
        Filter.or(
          Filter('assignedTo', isEqualTo: delegateId),
          Filter('assignedTo', isEqualTo: 'all'),
        ),
      );
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList(),
        );
  }

  @override
  Future<List<TaskModel>> getDelegateTasks(
    String organizationId,
    String delegateId,
    String companyId,
    String delegateRoleName, {
    TaskStatus? status,
    int? limit,
    dynamic lastDoc,
  }) async {
    Query query = _taskCollection(
      organizationId,
    ).where('companyId', isEqualTo: companyId);

    if (delegateRoleName == 'marketing') {
      query = query.where(
        Filter.or(
          Filter('assignedTo', isEqualTo: delegateId),
          Filter('assignedTo', isEqualTo: 'all'),
          Filter('assignedTo', isEqualTo: 'all_branch_marketing'),
        ),
      );
    } else if (delegateRoleName == 'marketingPromotion') {
      query = query.where(
        Filter.or(
          Filter('assignedTo', isEqualTo: delegateId),
          Filter('assignedTo', isEqualTo: 'all'),
          Filter('assignedTo', isEqualTo: 'all_marketing_promotion'),
        ),
      );
    } else {
      query = query.where(
        Filter.or(
          Filter('assignedTo', isEqualTo: delegateId),
          Filter('assignedTo', isEqualTo: 'all'),
        ),
      );
    }

    query = query.orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    if (lastDoc != null && lastDoc is DocumentSnapshot) {
      query = query.startAfterDocument(lastDoc);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.getResilient();
    return snapshot.docs.map((doc) => TaskModel.fromFirestore(doc)).toList();
  }

  @override
  Future<void> updateTask(String organizationId, TaskModel task) async {
    final ref = _taskCollection(organizationId).doc(task.uid);
    final data = task.toFirestore();
    List<String> oldPaths = const [];
    if (task.editedAt != null) {
      // Phase 2 leaves imageUrl empty on purpose (no public URL). Never
      // treat a missing imageUrl as "remove the image". Only clear
      // image fields when the sender explicitly saved a removal.
      final before = await ref.get();
      final beforeData = before.data() as Map<String, dynamic>?;
      oldPaths = _pathsFromDoc(beforeData);
      final newPaths = resolveTaskImagePaths(
        imagePath: task.imagePath,
        imagePaths: task.imagePaths,
      );
      data['imageUrl'] = FieldValue.delete();
      if (newPaths.isEmpty) {
        data['imagePath'] = FieldValue.delete();
        data['imagePaths'] = FieldValue.delete();
      } else {
        data['imagePath'] = newPaths.first;
        data['imagePaths'] = newPaths;
      }
    }
    await ref.update(data);
    final savedPaths = resolveTaskImagePaths(
      imagePath: task.imagePath,
      imagePaths: task.imagePaths,
    );
    final savedSet = savedPaths.toSet();
    // Delete previous objects only after the new paths (if any) are linked.
    for (final oldPath in oldPaths) {
      if (!savedSet.contains(oldPath)) {
        await _deleteImageQuietly(oldPath);
      }
    }
  }

  TaskProof _proofFromDoc(DocumentSnapshot snap) {
    final data = snap.data();
    final map = data is Map<String, dynamic>
        ? data
        : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
    final raw = map['imagePaths'];
    return TaskProof(
      uploaderUid: snap.id,
      imagePaths: resolveTaskProofPaths(
        raw is List
            ? [
                for (final item in raw)
                  if (item is String) item,
              ]
            : const [],
      ),
      uploadedByName: (map['uploadedByName'] as String?) ?? '',
      companyUID: (map['companyUID'] as String?) ?? '',
    );
  }

  @override
  Future<TaskProof?> getTaskProof(
    String organizationId,
    String taskId,
    String uploaderUid,
  ) async {
    final snap = await _taskCollection(
      organizationId,
    ).doc(taskId).collection('proofs').doc(uploaderUid).get();
    if (!snap.exists) return null;
    return _proofFromDoc(snap);
  }

  @override
  Future<List<TaskProof>> listTaskProofs(
    String organizationId,
    String taskId,
  ) async {
    final snap = await _taskCollection(
      organizationId,
    ).doc(taskId).collection('proofs').get();
    return [for (final doc in snap.docs) _proofFromDoc(doc)];
  }

  @override
  Future<void> saveTaskProof({
    required String organizationId,
    required String taskId,
    required String uploaderUid,
    required List<String> imagePaths,
    required String companyUID,
  }) async {
    final ref = _taskCollection(
      organizationId,
    ).doc(taskId).collection('proofs').doc(uploaderUid);
    final paths = resolveTaskProofPaths(imagePaths);
    if (paths.isEmpty) {
      final existing = await ref.get();
      final previous = existing.exists
          ? _proofFromDoc(existing).imagePaths
          : const <String>[];
      await ref.delete();
      for (final path in previous) {
        await _deleteImageQuietly(path);
      }
      return;
    }
    List<String> previous = const [];
    final existing = await ref.get();
    if (existing.exists) previous = _proofFromDoc(existing).imagePaths;
    // uploadedByName is server-set from the uploader's profile
    // (onTaskProofWritten). Merge so a client save never sends or clears it.
    await ref.set({
      'uploadedBy': uploaderUid,
      'companyUID': companyUID,
      'taskId': taskId,
      'imagePaths': paths,
    }, SetOptions(merge: true));
    final keep = paths.toSet();
    for (final path in previous) {
      if (!keep.contains(path)) {
        await _deleteImageQuietly(path);
      }
    }
  }

  @override
  Future<void> deleteTask(String organizationId, String taskId) async {
    final ref = _taskCollection(organizationId).doc(taskId);
    var imagePaths = <String>[];
    try {
      final snap = await ref.get();
      imagePaths = _pathsFromDoc(snap.data() as Map<String, dynamic>?);
    } catch (_) {}
    // Proof storage deletes are performed by onTaskDeleted (admin SDK);
    // the sender cannot delete another user's proof objects. Drop the
    // task document first so the trigger sees the remaining proof docs.
    await ref.delete();
    for (final path in imagePaths) {
      await _deleteImageQuietly(path);
    }
  }

  List<String> _pathsFromDoc(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['imagePaths'];
    return resolveTaskImagePaths(
      imagePath: data['imagePath'] as String?,
      imagePaths: raw is List
          ? [
              for (final item in raw)
                if (item is String) item,
            ]
          : const [],
    );
  }

  Future<void> _deleteImageQuietly(String path) async {
    try {
      await storage.ref(path).delete();
    } catch (e) {
      debugPrint('Task image delete failed: $e');
    }
  }
}
