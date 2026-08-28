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
  final String? penaltyId;
  final bool isRead;
  final DateTime createdAt;
  final List<String> deletedBy;

  const NotificationEntity({
    required this.id,
    required this.delegateUid,
    required this.organizationId,
    required this.companyId,
    required this.title,
    required this.body,
    required this.type,
    this.taskId,
    this.penaltyId,
    required this.isRead,
    required this.createdAt,
    this.deletedBy = const [],
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
        penaltyId,
        isRead,
        createdAt,
        deletedBy,
      ];
}
