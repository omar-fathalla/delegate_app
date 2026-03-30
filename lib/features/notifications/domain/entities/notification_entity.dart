import 'package:equatable/equatable.dart';

class NotificationEntity extends Equatable {
  final String id;
  final String delegateUid;
  final String organizationId;
  final String companyId;
  final String title;
  final String body;
  final String type;
  final String? taskId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationEntity({
    required this.id,
    required this.delegateUid,
    required this.organizationId,
    required this.companyId,
    required this.title,
    required this.body,
    required this.type,
    this.taskId,
    required this.isRead,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        delegateUid,
        organizationId,
        companyId,
        title,
        body,
        type,
        taskId,
        isRead,
        createdAt,
      ];
}
