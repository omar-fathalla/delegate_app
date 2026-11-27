import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:flutter/foundation.dart';

/// TAS-368: each recipient's own progress on a shared task («الكل»).
///
/// A shared task is one document for the whole company, so a delegate who
/// marked it done (or cancelled it) used to close it for everybody. Now a
/// delegate's status and notes go to
/// `organizations/{org}/tasks/{taskId}/completions/{selfId}` (same id as its
/// proof), and the shared task's own status stays the sender's.
class TaskCompletions {
  TaskCompletions(this.firestore);

  final FirebaseFirestore firestore;

  /// Sector keys a task can be sent to (one doc for many recipients).
  static const sharedAssignees = {
    'all',
    'الكل',
    'all_marketing_promotion',
    'all_branch_marketing',
  };

  static bool isShared(String assignedTo) =>
      sharedAssignees.contains(assignedTo.trim());

  CollectionReference<Map<String, dynamic>> _col(String org, String taskId) =>
      firestore
          .collection('organizations')
          .doc(org)
          .collection('tasks')
          .doc(taskId)
          .collection('completions');

  /// Writes the caller's own progress. A delegate never cancels.
  Future<void> save({
    required String organizationId,
    required String taskId,
    required String selfId,
    required TaskStatus status,
    String? notes,
  }) {
    if (status == TaskStatus.cancelled) {
      throw ArgumentError('A delegate cannot cancel a task (TAS-368).');
    }
    final now = FieldValue.serverTimestamp();
    return _col(organizationId, taskId).doc(selfId).set({
      'status': status.name,
      'notes': ?notes,
      if (status == TaskStatus.completed) 'completedAt': now,
      'updatedAt': now,
    });
  }

  /// The caller's own progress, or null when it has none yet.
  Future<({TaskStatus status, String? notes, DateTime? completedAt})?> mine({
    required String organizationId,
    required String taskId,
    required String selfId,
  }) async {
    try {
      final snap = await _col(organizationId, taskId).doc(selfId).get();
      final d = snap.data();
      if (d == null) return null;
      final status = TaskStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => TaskStatus.pending,
      );
      final at = d['completedAt'];
      return (
        status: status,
        notes: d['notes'] as String?,
        completedAt: at is Timestamp ? at.toDate() : null,
      );
    } catch (e) {
      debugPrint('TaskCompletions.mine failed: $e');
      return null;
    }
  }

  /// How many recipients marked the task done (staff view).
  Future<int> completedCount({
    required String organizationId,
    required String taskId,
  }) async {
    final agg = await _col(organizationId, taskId)
        .where('status', isEqualTo: TaskStatus.completed.name)
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Shows each shared task with the caller's own progress instead of the
  /// shared status (a colleague's «تم» is not this delegate's).
  Future<List<TaskEntity>> overlayMine({
    required String organizationId,
    required String selfId,
    required List<TaskEntity> tasks,
  }) {
    return Future.wait(tasks.map((t) async {
      if (!isShared(t.assignedTo)) return t;
      final m = await mine(organizationId: organizationId, taskId: t.uid, selfId: selfId);
      // The sender cancelled it: that stays visible to everyone.
      if (t.status == TaskStatus.cancelled) return t;
      return t.copyWith(
        status: m?.status ?? TaskStatus.pending,
        notes: m?.notes ?? '',
        completedAt: m?.completedAt,
      );
    }));
  }
}
