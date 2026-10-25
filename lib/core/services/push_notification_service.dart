import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channel for task notifications.
const AndroidNotificationChannel taskNotificationChannel =
    AndroidNotificationChannel(
      'task_notifications',
      'Task Notifications',
      description: 'Notifications for task assignments',
      importance: Importance.high,
    );

/// Handles Firebase Cloud Messaging setup, token management, and local
/// notification display.
class PushNotificationService {
  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  StreamSubscription<String>? _tokenRefreshSub;
  String? _initializedUid;

  /// Callback invoked when a notification is tapped.
  /// Receives the notification data payload.
  static void Function(Map<String, dynamic> data)? onNotificationTap;

  PushNotificationService({
    required FirebaseFirestore firestore,
    required FirebaseMessaging messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _firestore = firestore,
        _messaging = messaging,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin();

  /// Initializes FCM: requests permissions, saves token, subscribes to topics,
  /// and sets up foreground/tap handlers.
  Future<void> initialize(String delegateUid) async {
    if (kIsWeb) return;
    if (_initializedUid == delegateUid) {
      debugPrint('FCM: Already initialized for delegate $delegateUid');
      return;
    }
    _initializedUid = delegateUid;

    // 1. Initialize local notifications first (fast, local, no network)
    try {
      await _initLocalNotifications();
    } catch (e) {
      debugPrint('FCM: Local notifications init error: $e');
    }

    // 2. Set up foreground/background message stream listeners
    try {
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } catch (e) {
      debugPrint('FCM: Message listener setup error: $e');
    }

    // 3. Check for initial message (when app opened from terminated state)
    try {
      final initialMessage = await _messaging
          .getInitialMessage()
          .timeout(const Duration(seconds: 3));
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      debugPrint('FCM: getInitialMessage error: $e');
    }

    // 4. Request permission safely with timeout (non-blocking)
    try {
      await _messaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('FCM: Permission request timeout or error: $e');
    }

    // 5. Get and save FCM token safely with timeout
    try {
      final token = await _messaging
          .getToken()
          .timeout(const Duration(seconds: 4));
      if (token != null) {
        await _saveToken(delegateUid, token);
      }
    } catch (e) {
      debugPrint('FCM: getToken error: $e');
    }

    // 6. Listen for token refresh
    try {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        _saveToken(delegateUid, newToken);
      });
    } catch (e) {
      debugPrint('FCM: onTokenRefresh listen error: $e');
    }

    // 7. Subscribe to app_updates topic safely with timeout
    try {
      await _messaging
          .subscribeToTopic('app_updates')
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('FCM: subscribeToTopic error: $e');
    }

    debugPrint('FCM: Initialized for delegate $delegateUid');
  }

  /// Drops this user's push registration. Network steps are best-effort and
  /// time out so logout is not stuck offline.
  Future<void> clearToken(String delegateUid) async {
    if (kIsWeb) return;
    _initializedUid = null;
    try {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
    } catch (_) {}
    try {
      await _messaging
          .unsubscribeFromTopic('app_updates')
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('FCM: unsubscribeFromTopic error: $e');
    }
    try {
      await _messaging.deleteToken().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('FCM: deleteToken error: $e');
    }
    try {
      await _firestore
          .collection('fcm_tokens')
          .doc(delegateUid)
          .delete()
          .timeout(const Duration(seconds: 2));
      debugPrint('FCM: Token cleared for $delegateUid');
    } catch (e) {
      debugPrint('FCM: Error clearing token: $e');
    }
  }

  Future<void> _saveToken(String delegateUid, String token) async {
    try {
      await _firestore
          .collection('fcm_tokens')
          .doc(delegateUid)
          .set({
            'token': token,
            'updatedAt': FieldValue.serverTimestamp(),
            'platform': Platform.isIOS ? 'ios' : 'android',
          })
          .timeout(const Duration(seconds: 4));
      debugPrint('FCM: Token saved for $delegateUid');
    } catch (e) {
      debugPrint('FCM: Error saving token: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle tap on local notification
        if (response.payload != null) {
          final parts = response.payload!.split('|');
          if (parts.length >= 3) {
            onNotificationTap?.call({
              'type': parts[0],
              'taskId': parts[1],
              'organizationId': parts[2],
            });
          }
        }
      },
    );

    // Create Android notification channel
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(taskNotificationChannel);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM foreground message: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    final android = notification.android;
    final data = message.data;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          taskNotificationChannel.id,
          taskNotificationChannel.name,
          channelDescription: taskNotificationChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: android?.smallIcon ?? '@mipmap/launcher_icon',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: '${data['type']}|${data['taskId']}|${data['organizationId']}',
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('FCM notification tapped: ${message.data}');
    onNotificationTap?.call(message.data);
  }
}
