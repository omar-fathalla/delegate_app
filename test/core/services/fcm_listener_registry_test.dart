// TAS-80: logout + login used to add a second onMessage listener, so every
// foreground push was shown twice.
import 'dart:async';

import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listenOnce twice delivers each message once', () async {
    final messages = StreamController<RemoteMessage>.broadcast();
    final opened = StreamController<RemoteMessage>.broadcast();
    final registry = FcmListenerRegistry();
    var foreground = 0;
    var taps = 0;
    for (var login = 0; login < 2; login++) {
      registry.listenOnce(
        onMessage: messages.stream,
        onMessageOpenedApp: opened.stream,
        onForeground: (_) => foreground++,
        onTap: (_) => taps++,
      );
    }
    messages.add(const RemoteMessage(messageId: 'm1'));
    opened.add(const RemoteMessage(messageId: 'm2'));
    await Future<void>.delayed(Duration.zero);
    expect(foreground, 1);
    expect(taps, 1);
    expect(registry.isListening, isTrue);

    await registry.cancel();
    messages.add(const RemoteMessage(messageId: 'm3'));
    await Future<void>.delayed(Duration.zero);
    expect(foreground, 1);
    expect(registry.isListening, isFalse);
    await messages.close();
    await opened.close();
  });
}
