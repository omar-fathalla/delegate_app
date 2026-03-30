part of 'notification_bloc.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotifications extends NotificationEvent {
  final String delegateUid;
  final String organizationId;

  const LoadNotifications({
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId];
}

class SubscribeToUnreadCount extends NotificationEvent {
  final String delegateUid;
  final String organizationId;

  const SubscribeToUnreadCount({
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId];
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

  const MarkAsRead({
    required this.notificationId,
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [notificationId, delegateUid, organizationId];
}

class MarkAllAsRead extends NotificationEvent {
  final String delegateUid;
  final String organizationId;

  const MarkAllAsRead({
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId];
}
