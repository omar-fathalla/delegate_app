import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_model.dart';

abstract class NotificationLocalDataSource {
  Future<List<NotificationModel>> getCachedNotifications(String userKey);
  Future<void> cacheNotifications(String userKey, List<NotificationModel> notifications);
  Future<void> markAsReadInCache(String userKey, String notificationId);
  Future<void> markAllAsReadInCache(String userKey);
  Future<void> deleteNotificationInCache(String userKey, String notificationId);
}

class NotificationLocalDataSourceImpl implements NotificationLocalDataSource {
  final SharedPreferences sharedPreferences;

  NotificationLocalDataSourceImpl({required this.sharedPreferences});

  String _cacheKey(String userKey) => 'cached_notifications_$userKey';

  @override
  Future<List<NotificationModel>> getCachedNotifications(String userKey) async {
    try {
      final jsonString = sharedPreferences.getString(_cacheKey(userKey));
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        return jsonList
            .map((item) => NotificationModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<void> cacheNotifications(String userKey, List<NotificationModel> notifications) async {
    try {
      final jsonList = notifications.map((n) => n.toJson()).toList();
      await sharedPreferences.setString(_cacheKey(userKey), jsonEncode(jsonList));
    } catch (_) {}
  }

  @override
  Future<void> markAsReadInCache(String userKey, String notificationId) async {
    try {
      final cached = await getCachedNotifications(userKey);
      final updated = cached.map((n) {
        if (n.id == notificationId) {
          return NotificationModel(
            id: n.id,
            delegateUid: n.delegateUid,
            organizationId: n.organizationId,
            companyId: n.companyId,
            title: n.title,
            body: n.body,
            type: n.type,
            taskId: n.taskId,
            penaltyId: n.penaltyId,
            isRead: true,
            createdAt: n.createdAt,
            deletedBy: n.deletedBy,
          );
        }
        return n;
      }).toList();
      await cacheNotifications(userKey, updated);
    } catch (_) {}
  }

  @override
  Future<void> markAllAsReadInCache(String userKey) async {
    try {
      final cached = await getCachedNotifications(userKey);
      final updated = cached.map((n) {
        return NotificationModel(
          id: n.id,
          delegateUid: n.delegateUid,
          organizationId: n.organizationId,
          companyId: n.companyId,
          title: n.title,
          body: n.body,
          type: n.type,
          taskId: n.taskId,
          penaltyId: n.penaltyId,
          isRead: true,
          createdAt: n.createdAt,
          deletedBy: n.deletedBy,
        );
      }).toList();
      await cacheNotifications(userKey, updated);
    } catch (_) {}
  }

  @override
  Future<void> deleteNotificationInCache(String userKey, String notificationId) async {
    try {
      final cached = await getCachedNotifications(userKey);
      final updated = cached.where((n) => n.id != notificationId).toList();
      await cacheNotifications(userKey, updated);
    } catch (_) {}
  }
}
