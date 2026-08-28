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
    super.penaltyId,
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
      penaltyId: data['penaltyId'] ?? data['penaltyID'],
      isRead: data['isRead'] ?? data['read'] ?? false,
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
      'penaltyId': penaltyId,
      'isRead': isRead,
      'read': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedBy': deletedBy,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delegateUid': delegateUid,
      'organizationId': organizationId,
      'companyId': companyId,
      'title': title,
      'body': body,
      'type': type,
      'taskId': taskId,
      'penaltyId': penaltyId,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      'deletedBy': deletedBy,
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final rawDeletedBy = json['deletedBy'];
    final List<String> deletedBy = rawDeletedBy is List
        ? rawDeletedBy.map((e) => e.toString()).toList()
        : const [];

    return NotificationModel(
      id: json['id'] ?? '',
      delegateUid: json['delegateUid'] ?? '',
      organizationId: json['organizationId'] ?? '',
      companyId: json['companyId'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      type: json['type'] ?? 'general',
      taskId: json['taskId'],
      penaltyId: json['penaltyId'],
      isRead: json['isRead'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      deletedBy: deletedBy,
    );
  }
}
