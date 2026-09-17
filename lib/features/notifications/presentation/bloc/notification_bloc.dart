import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_cached_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_notification_for_user.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_all_notifications_for_user.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_unread_count.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_all_notifications_read.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_notification_read.dart';
import 'package:equatable/equatable.dart';

part 'notification_event.dart';
part 'notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final GetNotifications getNotifications;
  final GetCachedNotifications? getCachedNotifications;
  final GetUnreadCount getUnreadCount;
  final MarkNotificationRead markNotificationRead;
  final MarkAllNotificationsRead markAllNotificationsRead;
  final DeleteNotificationForUser deleteNotificationForUser;
  final DeleteAllNotificationsForUser deleteAllNotificationsForUser;

  StreamSubscription<int>? _unreadCountSubscription;
  int _currentUnreadCount = 0;
  String? _currentUserRole;
  DateTime? _currentAccountCreatedAt;

  NotificationBloc({
    required this.getNotifications,
    this.getCachedNotifications,
    required this.getUnreadCount,
    required this.markNotificationRead,
    required this.markAllNotificationsRead,
    required this.deleteNotificationForUser,
    required this.deleteAllNotificationsForUser,
  }) : super(NotificationInitial()) {
    on<LoadNotifications>(_onLoadNotifications);
    on<SubscribeToUnreadCount>(_onSubscribeToUnreadCount);
    on<UnreadCountUpdated>(_onUnreadCountUpdated);
    on<MarkAsRead>(_onMarkAsRead);
    on<MarkAllAsRead>(_onMarkAllAsRead);
    on<DeleteNotificationRequested>(_onDeleteNotification);
    on<DeleteAllNotificationsRequested>(_onDeleteAllNotifications);
  }

  Future<void> _onLoadNotifications(
    LoadNotifications event,
    Emitter<NotificationState> emit,
  ) async {
    if (event.userRole != null) _currentUserRole = event.userRole;
    if (event.accountCreatedAt != null) {
      _currentAccountCreatedAt = event.accountCreatedAt;
    }

    final role = event.userRole ?? _currentUserRole;
    final isDelegate = role != null &&
        role.toLowerCase().contains('delegate') &&
        !role.toLowerCase().contains('supervisor') &&
        !role.toLowerCase().contains('admin');
    final createdAt = event.accountCreatedAt ?? _currentAccountCreatedAt;

    // 1. Instant Cache-First Load (0 ms)
    List<NotificationEntity> cachedList = [];
    if (getCachedNotifications != null) {
      try {
        cachedList = await getCachedNotifications!(event.delegateUid);
        if (cachedList.isNotEmpty) {
          if (isDelegate) {
            cachedList = cachedList.where((n) {
              final isAttendance = n.type == 'attendance_check_in' ||
                  n.type == 'attendance_check_out';
              return !isAttendance;
            }).toList();
          }
          if (createdAt != null) {
            final cutoff = createdAt.subtract(const Duration(minutes: 5));
            cachedList = cachedList
                .where((n) => !n.createdAt.isBefore(cutoff))
                .toList();
          }

          if (cachedList.isNotEmpty) {
            emit(
              NotificationLoaded(
                notifications: cachedList,
                unreadCount: _currentUnreadCount > 0
                    ? _currentUnreadCount
                    : cachedList.where((n) => !n.isRead).length,
              ),
            );
          }
        }
      } catch (_) {}
    }

    if (cachedList.isEmpty) {
      emit(NotificationLoading());
    }

    // 2. Background Remote Sync (Stale-While-Revalidate)
    final result = await getNotifications(
      GetNotificationsParams(
        delegateUid: event.delegateUid,
        organizationId: event.organizationId,
        phoneNumber: event.phoneNumber,
        userRole: role,
        accountCreatedAt: createdAt,
      ),
    );

    result.fold(
      (failure) {
        if (cachedList.isEmpty) {
          emit(NotificationError(failure.message));
        }
      },
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
    if (event.userRole != null) _currentUserRole = event.userRole;
    if (event.accountCreatedAt != null) {
      _currentAccountCreatedAt = event.accountCreatedAt;
    }

    await _unreadCountSubscription?.cancel();

    _unreadCountSubscription =
        getUnreadCount(
          GetUnreadCountParams(
            delegateUid: event.delegateUid,
            organizationId: event.organizationId,
            phoneNumber: event.phoneNumber,
            userRole: event.userRole ?? _currentUserRole,
            accountCreatedAt: event.accountCreatedAt ?? _currentAccountCreatedAt,
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
        userRole: _currentUserRole,
        accountCreatedAt: _currentAccountCreatedAt,
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
        userRole: _currentUserRole,
        accountCreatedAt: _currentAccountCreatedAt,
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

  Future<void> _onDeleteAllNotifications(
    DeleteAllNotificationsRequested event,
    Emitter<NotificationState> emit,
  ) async {
    // 1. Instant Optimistic UI Clear (0 ms)
    _currentUnreadCount = 0;
    emit(const NotificationLoaded(notifications: [], unreadCount: 0));

    // 2. Perform Firestore soft-deletion
    await deleteAllNotificationsForUser(
      DeleteAllNotificationsForUserParams(
        notificationIds: event.notificationIds,
        userUid: event.delegateUid,
        phoneNumber: event.phoneNumber,
      ),
    );
  }

  @override
  Future<void> close() {
    _unreadCountSubscription?.cancel();
    return super.close();
  }
}
