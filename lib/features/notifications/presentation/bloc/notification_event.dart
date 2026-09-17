part of 'notification_bloc.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotifications extends NotificationEvent {
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;
  final String? userRole;
  final DateTime? accountCreatedAt;

  const LoadNotifications({
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
    this.userRole,
    this.accountCreatedAt,
  });

  @override
  List<Object?> get props => [
        delegateUid,
        organizationId,
        phoneNumber,
        userRole,
        accountCreatedAt,
      ];
}

class SubscribeToUnreadCount extends NotificationEvent {
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;
  final String? userRole;
  final DateTime? accountCreatedAt;

  const SubscribeToUnreadCount({
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
    this.userRole,
    this.accountCreatedAt,
  });

  @override
  List<Object?> get props => [
        delegateUid,
        organizationId,
        phoneNumber,
        userRole,
        accountCreatedAt,
      ];
}

class UnreadCountUpdated extends NotificationEvent {
  final int count;

  const UnreadCountUpdated(this.count);

  @override
  List<Object?> get props => [count];
}

class MarkAsRead extends NotificationEvent {
  final String notificationId;
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;

  const MarkAsRead({
    required this.notificationId,
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [notificationId, delegateUid, organizationId, phoneNumber];
}

class MarkAllAsRead extends NotificationEvent {
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;

  const MarkAllAsRead({
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId, phoneNumber];
}

class DeleteNotificationRequested extends NotificationEvent {
  final String notificationId;
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;

  const DeleteNotificationRequested({
    required this.notificationId,
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [notificationId, delegateUid, organizationId, phoneNumber];
}

class DeleteAllNotificationsRequested extends NotificationEvent {
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;
  final List<String> notificationIds;

  const DeleteAllNotificationsRequested({
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
    required this.notificationIds,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId, phoneNumber, notificationIds];
}


