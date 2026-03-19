import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles Firebase Cloud Messaging setup and topic subscription.
class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initializes FCM: requests permissions and subscribes to topics.
  Future<void> initialize() async {
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

    // Subscribe to app_updates topic for changelog notifications
    await _messaging.subscribeToTopic('app_updates');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    debugPrint('FCM: Initialized and subscribed to app_updates topic');
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM foreground message: ${message.notification?.title}');
  }
}
