import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_notification_for_user.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_unread_count.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_all_notifications_read.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_notification_read.dart';
import 'package:equatable/equatable.dart';

part 'notification_event.dart';
part 'notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final GetNotifications getNotifications;
  final GetUnreadCount getUnreadCount;
  final MarkNotificationRead markNotificationRead;
  final MarkAllNotificationsRead markAllNotificationsRead;
  final DeleteNotificationForUser deleteNotificationForUser;

  StreamSubscription<int>? _unreadCountSubscription;
  int _currentUnreadCount = 0;

  NotificationBloc({
    required this.getNotifications,
    required this.getUnreadCount,
    required this.markNotificationRead,
    required this.markAllNotificationsRead,
    required this.deleteNotificationForUser,
  }) : super(NotificationInitial()) {
    on<LoadNotifications>(_onLoadNotifications);
    on<SubscribeToUnreadCount>(_onSubscribeToUnreadCount);
    on<UnreadCountUpdated>(_onUnreadCountUpdated);
    on<MarkAsRead>(_onMarkAsRead);
    on<MarkAllAsRead>(_onMarkAllAsRead);
    on<DeleteNotificationRequested>(_onDeleteNotification);
  }

  Future<void> _onLoadNotifications(
    LoadNotifications event,
    Emitter<NotificationState> emit,
  ) async {
    emit(NotificationLoading());

    final result = await getNotifications(
      GetNotificationsParams(
        delegateUid: event.delegateUid,
        organizationId: event.organizationId,
        phoneNumber: event.phoneNumber,
      ),
    );

    result.fold(
      (failure) => emit(NotificationError(failure.message)),
      (notifications) => emit(
        NotificationLoaded(
          notifications: notifications,
          unreadCount: _currentUnreadCount > 0
              ? _currentUnreadCount
              : notifications.where((n) => !n.isRead).length,
        ),
      ),
    );
  }

  Future<void> _onSubscribeToUnreadCount(
    SubscribeToUnreadCount event,
    Emitter<NotificationState> emit,
  ) async {
    await _unreadCountSubscription?.cancel();

    _unreadCountSubscription =
        getUnreadCount(
          GetUnreadCountParams(
            delegateUid: event.delegateUid,
            organizationId: event.organizationId,
            phoneNumber: event.phoneNumber,
          ),
        ).listen((count) {
          add(UnreadCountUpdated(count));
        });
  }

  void _onUnreadCountUpdated(
    UnreadCountUpdated event,
    Emitter<NotificationState> emit,
  ) {
    _currentUnreadCount = event.count;
    if (state is NotificationLoaded) {
      emit((state as NotificationLoaded).copyWith(unreadCount: event.count));
    } else {
      emit(NotificationLoaded(notifications: const [], unreadCount: event.count));
    }
  }

  Future<void> _onMarkAsRead(
    MarkAsRead event,
    Emitter<NotificationState> emit,
  ) async {
    await markNotificationRead(
      MarkNotificationReadParams(notificationId: event.notificationId),
    );

    // Reload notifications
    add(
      LoadNotifications(
        delegateUid: event.delegateUid,
        organizationId: event.organizationId,
        phoneNumber: event.phoneNumber,
      ),
    );
  }

  Future<void> _onMarkAllAsRead(
    MarkAllAsRead event,
    Emitter<NotificationState> emit,
  ) async {
    await markAllNotificationsRead(
      MarkAllNotificationsReadParams(
        delegateUid: event.delegateUid,
        organizationId: event.organizationId,
      ),
    );

    // Reload notifications
    add(
      LoadNotifications(
        delegateUid: event.delegateUid,
        organizationId: event.organizationId,
        phoneNumber: event.phoneNumber,
      ),
    );
  }

  Future<void> _onDeleteNotification(
    DeleteNotificationRequested event,
    Emitter<NotificationState> emit,
  ) async {
    if (state is NotificationLoaded) {
      final currentList = (state as NotificationLoaded).notifications;
      final updatedList =
          currentList.where((n) => n.id != event.notificationId).toList();
      emit(
        (state as NotificationLoaded).copyWith(
          notifications: updatedList,
          unreadCount: updatedList.where((n) => !n.isRead).length,
        ),
      );
    }

    await deleteNotificationForUser(
      DeleteNotificationForUserParams(
        notificationId: event.notificationId,
        userUid: event.delegateUid,
      ),
    );
  }

  @override
  Future<void> close() {
    _unreadCountSubscription?.cancel();
    return super.close();
  }
}
