import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide online/offline state plus the last moment we were online
/// (used as "last updated" in the offline banner).
class ConnectivityStatus {
  ConnectivityStatus._();
  static final ConnectivityStatus instance = ConnectivityStatus._();

  static const _prefsKey = 'last_online_at';

  final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> lastOnlineAt = ValueNotifier<DateTime?>(null);
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    try {
      SharedPreferences.getInstance().then((p) {
        final ms = p.getInt(_prefsKey);
        if (ms != null && lastOnlineAt.value == null) {
          lastOnlineAt.value = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      }).catchError((_) {});
      _sub = Connectivity().onConnectivityChanged.listen(_apply, onError: (_) {});
      recheck();
    } catch (_) {
      // Plugin unavailable (tests): stay "online".
    }
  }

  Future<bool> recheck() async {
    try {
      _apply(await Connectivity().checkConnectivity());
    } catch (_) {}
    return !isOffline.value;
  }

  void _apply(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    isOffline.value = offline;
    if (!offline) markOnline();
  }

  void markOnline() {
    final now = DateTime.now();
    lastOnlineAt.value = now;
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_prefsKey, now.millisecondsSinceEpoch))
        .catchError((_) => false);
  }

  @visibleForTesting
  void debugSetOffline(bool v) => isOffline.value = v;

  void dispose() => _sub?.cancel();
}
