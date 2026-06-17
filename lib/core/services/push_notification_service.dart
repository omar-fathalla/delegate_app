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

  /// Callback invoked when a notification is tapped.
  /// Receives the notification data payload.
  static void Function(Map<String, dynamic> data)? onNotificationTap;

  PushNotificationService({
    required FirebaseFirestore firestore,
    required FirebaseMessaging messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _firestore = firestore,
       _messaging = messaging,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  /// Initializes FCM: requests permissions, saves token, subscribes to topics,
  /// and sets up foreground/tap handlers.
  Future<void> initialize(String delegateUid) async {
    // Request permission (iOS/macOS require explicit permission)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM: User denied notification permissions');
      return;
    }

    // Save FCM token
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(delegateUid, token);
    }

    // Listen for token refresh
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      _saveToken(delegateUid, newToken);
    });

    // Subscribe to app_updates topic for changelog notifications
    await _messaging.subscribeToTopic('app_updates');

    // Initialize local notifications for foreground display
    await _initLocalNotifications();

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification tap when app was terminated
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    debugPrint('FCM: Initialized for delegate $delegateUid');
  }

  /// Removes the FCM token from Firestore. Call on logout.
  Future<void> clearToken(String delegateUid) async {
    try {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      await _firestore.collection('fcm_tokens').doc(delegateUid).delete();
      debugPrint('FCM: Token cleared for $delegateUid');
    } catch (e) {
      debugPrint('FCM: Error clearing token: $e');
    }
  }

  Future<void> _saveToken(String delegateUid, String token) async {
    try {
      await _firestore.collection('fcm_tokens').doc(delegateUid).set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
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
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
