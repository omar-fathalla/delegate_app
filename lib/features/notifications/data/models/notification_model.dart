import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';

class NotificationModel extends NotificationEntity {
  const NotificationModel({
    required super.id,
    required super.delegateUid,
    required super.organizationId,
    required super.companyId,
    required super.title,
    required super.body,
    required super.type,
    super.taskId,
    required super.isRead,
    required super.createdAt,
    super.deletedBy,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawDeletedBy = data['deletedBy'];
    final List<String> deletedBy = rawDeletedBy is List
        ? rawDeletedBy.map((e) => e.toString()).toList()
        : const [];

    return NotificationModel(
      id: doc.id,
      delegateUid: data['delegateUid'] ?? '',
      organizationId: data['organizationId'] ?? '',
      companyId: data['companyId'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: data['type'] ?? 'general',
      taskId: data['taskId'],
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedBy: deletedBy,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'delegateUid': delegateUid,
      'organizationId': organizationId,
      'companyId': companyId,
      'title': title,
      'body': body,
      'type': type,
      'taskId': taskId,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedBy': deletedBy,
    };
  }
}
