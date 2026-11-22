import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TAS-76: drops the previous user's Firestore disk cache on a shared device.
///
/// Logout only marks the reset ([markPending]). It runs later, before any
/// Firestore use of the next session: at app start and when the login screen
/// opens ([runIfPending]). By then the old session's screens and listeners
/// are gone, so `terminate()` does not break a live listener.
///
/// Writes the device has not uploaded yet (an offline check-in, for example)
/// are never thrown away: if `waitForPendingWrites` does not finish in time,
/// the reset waits for the next chance and the mark stays.
///
/// Web keeps no disk cache (persistence is mobile only), so it is a no-op
/// there.
class FirestoreCacheReset {
  FirestoreCacheReset({
    required this.prefs,
    Future<void> Function()? waitForPendingWrites,
    Future<void> Function()? terminate,
    Future<void> Function()? clearPersistence,
    this.pendingWritesTimeout = const Duration(seconds: 3),
    bool? isWeb,
  })  : _wait = waitForPendingWrites ??
            (() => FirebaseFirestore.instance.waitForPendingWrites()),
        _terminate =
            terminate ?? (() => FirebaseFirestore.instance.terminate()),
        _clear = clearPersistence ??
            (() => FirebaseFirestore.instance.clearPersistence()),
        _isWeb = isWeb ?? kIsWeb;

  static const pendingKey = 'firestore_cache_reset_pending';

  final SharedPreferences prefs;
  final Duration pendingWritesTimeout;
  final Future<void> Function() _wait;
  final Future<void> Function() _terminate;
  final Future<void> Function() _clear;
  final bool _isWeb;

  static Future<bool>? _running;

  bool get isPending => prefs.getBool(pendingKey) ?? false;

  /// Called on logout, after the session's listeners were cancelled.
  Future<void> markPending() async {
    if (_isWeb) return;
    await prefs.setBool(pendingKey, true);
  }

  /// TAS-244: set once this build has dropped a cache from older builds.
  static const legacyDoneKey = 'firestore_cache_legacy_reset_v1';

  /// TAS-244: a logout done by an older build (before TAS-76) never marked
  /// the reset, so earlier users' documents stay in the cache. On the first
  /// start of this build, mark it once; [runIfPending] then drops it before
  /// anything reads Firestore. Unsent writes still postpone it, as usual.
  Future<void> markLegacyCacheOnce() async {
    if (_isWeb || (prefs.getBool(legacyDoneKey) ?? false)) return;
    await prefs.setBool(pendingKey, true);
    await prefs.setBool(legacyDoneKey, true);
  }

  /// Clears the cache when a logout asked for it. Returns whether it did.
  /// Concurrent callers share one run.
  Future<bool> runIfPending() {
    if (_isWeb || !isPending) return Future.value(false);
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<bool> _run() async {
    try {
      await _wait().timeout(pendingWritesTimeout);
    } on TimeoutException {
      debugPrint('Firestore cache reset postponed: writes still pending.');
      return false;
    } catch (e) {
      debugPrint('Firestore cache reset postponed: $e');
      return false;
    }
    try {
      await _terminate();
      await _clear();
      await prefs.remove(pendingKey);
      return true;
    } catch (e) {
      debugPrint('Firestore cache reset failed, will retry: $e');
      return false;
    }
  }

  @visibleForTesting
  static void debugReset() => _running = null;
}
