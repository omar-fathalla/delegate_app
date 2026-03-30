import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';

abstract class NotificationRemoteDataSource {
  Future<List<NotificationModel>> getNotifications(
    String delegateUid,
    String organizationId,
  );

  Stream<int> getUnreadCount(String delegateUid, String organizationId);

  Future<void> markAsRead(String notificationId);

  Future<void> markAllAsRead(String delegateUid, String organizationId);
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final FirebaseFirestore firestore;

  NotificationRemoteDataSourceImpl({required this.firestore});

  CollectionReference get _collection => firestore.collection('notifications');

  @override
  Future<List<NotificationModel>> getNotifications(
    String delegateUid,
    String organizationId,
  ) async {
    final snapshot = await _collection
        .where('delegateUid', isEqualTo: delegateUid)
        .where('organizationId', isEqualTo: organizationId)
        .limit(50)
        .get();

    // Sort in memory instead of in Firestore
    final docs = snapshot.docs;
    docs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>?;
      final bData = b.data() as Map<String, dynamic>?;
      final aTime =
          (aData?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final bTime =
          (bData?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      return bTime.compareTo(aTime); // descending
    });

    return docs.map((doc) => NotificationModel.fromFirestore(doc)).toList();
  }

  @override
  Stream<int> getUnreadCount(String delegateUid, String organizationId) {
    return _collection
        .where('delegateUid', isEqualTo: delegateUid)
        .where('organizationId', isEqualTo: organizationId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _collection.doc(notificationId).update({'isRead': true});
  }

  @override
  Future<void> markAllAsRead(String delegateUid, String organizationId) async {
    final snapshot = await _collection
        .where('delegateUid', isEqualTo: delegateUid)
        .where('organizationId', isEqualTo: organizationId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
