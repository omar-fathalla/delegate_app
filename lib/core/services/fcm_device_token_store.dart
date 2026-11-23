import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// TAS-258: one FCM token doc per app install, so a user on two devices gets
/// pushes on both, and logging out on one device keeps the other one.
///
/// Layout:
/// - `fcm_tokens/{uid}` `{token, updatedAt, platform}`: the legacy doc, still
///   written exactly as before so live functions and old app versions keep
///   working during the transition.
/// - `fcm_tokens/{uid}/devices/{deviceId}` `{token, platform, updatedAt}`.
///
/// Every network step is best effort with a timeout, and a failure on one doc
/// never blocks the other (the device rule may not be deployed yet).
class FcmDeviceTokenStore {
  FcmDeviceTokenStore({
    required FirebaseFirestore firestore,
    required Future<String> Function() deviceId,
    required String platform,
  })  : _firestore = firestore,
        _deviceId = deviceId,
        _platform = platform;

  final FirebaseFirestore _firestore;
  final Future<String> Function() _deviceId;
  final String _platform;

  /// Last token this install saved, used on logout when the device doc
  /// cannot be read.
  String? _lastSavedToken;

  static const Duration writeTimeout = Duration(seconds: 4);
  static const Duration readTimeout = Duration(seconds: 3);
  static const Duration deleteTimeout = Duration(seconds: 7);

  DocumentReference<Map<String, dynamic>> _legacyRef(String uid) =>
      _firestore.collection('fcm_tokens').doc(uid);

  DocumentReference<Map<String, dynamic>> _deviceRef(String uid, String id) =>
      _legacyRef(uid).collection('devices').doc(id);

  /// Writes the legacy doc and this device's doc. Also used on token refresh.
  Future<void> save(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) return;
    _lastSavedToken = token;
    final legacy = _guard('save legacy token', () {
      return _legacyRef(uid).set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': _platform,
      }).timeout(writeTimeout);
    });
    final device = _guard('save device token', () async {
      final id = await _deviceId();
      if (id.isEmpty) return;
      await _deviceRef(uid, id).set({
        'token': token,
        'platform': _platform,
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(writeTimeout);
    });
    await Future.wait([legacy, device]);
  }

  /// Logout: deletes only this device's doc. The legacy doc is deleted only
  /// when it still holds this device's token (another device, or an old app
  /// version, may have written its own token there since).
  Future<void> clear(String uid) async {
    if (uid.isEmpty) return;
    var id = '';
    try {
      id = await _deviceId();
    } catch (e) {
      debugPrint('FCM: device id error: $e');
    }
    final deviceRef = id.isEmpty ? null : _deviceRef(uid, id);

    String? deviceToken;
    String? legacyToken;
    var legacyKnown = false;
    await Future.wait([
      if (deviceRef != null)
        _guard('read device token', () async {
          final snap = await deviceRef.get().timeout(readTimeout);
          deviceToken = _tokenOf(snap.data());
        }),
      _guard('read legacy token', () async {
        final snap = await _legacyRef(uid).get().timeout(readTimeout);
        legacyToken = _tokenOf(snap.data());
        legacyKnown = true;
      }),
    ]);

    final mine = deviceToken ?? _lastSavedToken;
    _lastSavedToken = null;
    // Unknown own token: keep the old behaviour (delete the legacy doc) so a
    // logged-out install does not keep receiving this user's pushes.
    final deleteLegacy = !legacyKnown ||
        mine == null ||
        (legacyToken != null && legacyToken == mine);

    await Future.wait([
      if (deviceRef != null)
        _guard('delete device token', () {
          return deviceRef.delete().timeout(deleteTimeout);
        }),
      if (deleteLegacy && (!legacyKnown || legacyToken != null))
        _guard('delete legacy token', () {
          return _legacyRef(uid).delete().timeout(deleteTimeout);
        }),
    ]);
    debugPrint('FCM: Token cleared for $uid (legacy deleted: $deleteLegacy)');
  }

  static String? _tokenOf(Map<String, dynamic>? data) {
    final t = data?['token'];
    return t is String && t.isNotEmpty ? t : null;
  }

  static Future<void> _guard(String what, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      debugPrint('FCM: $what error: $e');
    }
  }
}

/// A random id per app install, kept in SharedPreferences. FCM tokens are per
/// install too, so this is the right key for `devices/{deviceId}` (the device
/// binding id on Android is the build id, shared by many phones).
class FcmInstallId {
  FcmInstallId._();

  static const String prefsKey = 'fcm_install_device_id';
  static String? _cached;

  static Future<String> load([SharedPreferences? prefs]) async {
    final cached = _cached;
    if (cached != null) return cached;
    final p = prefs ?? await SharedPreferences.getInstance();
    var id = p.getString(prefsKey) ?? '';
    if (id.isEmpty) {
      id = const Uuid().v4();
      await p.setString(prefsKey, id);
    }
    return _cached = id;
  }

  @visibleForTesting
  static void resetCache() => _cached = null;
}
