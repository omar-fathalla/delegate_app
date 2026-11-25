import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// TAS-28 phase 0: the signed-in delegate's own document id.
///
/// `delegateLoginV2` puts the delegate document id in the `delegateId` token
/// claim. Today the Auth uid is that same id, so reading the claim changes
/// nothing; phase 1 gives new logins a different uid (`dlg_<hash>`), and code
/// that used `currentUser.uid` as the delegate id would then write the wrong
/// id. Use [DelegateIdentity.current] (sync) or [DelegateIdentity.refresh]
/// (async) instead of `FirebaseAuth.instance.currentUser?.uid` wherever the
/// value means "my delegate document id".
///
/// Keep `currentUser.uid` for Auth-keyed data: `users/{uid}`,
/// `fcm_tokens/{uid}`, `deviceBindings/{uid}` and staff accounts.
class DelegateIdentity {
  DelegateIdentity._();

  static String? _cachedUid;
  static String? _cachedDelegateId;

  /// Pure rule: the `delegateId` claim when it is a non-empty string on a
  /// delegate token, else [uid]. Staff tokens always get [uid].
  static String? fromClaims({
    required String? uid,
    Map<String, dynamic>? claims,
  }) {
    final role = claims?['role'];
    final claim = claims?['delegateId'];
    if (role == 'delegate' && claim is String && claim.trim().isNotEmpty) {
      return claim.trim();
    }
    final u = uid?.trim() ?? '';
    return u.isEmpty ? null : u;
  }

  /// Sync accessor: the cached claim for the current Auth user, else its uid
  /// (equal to the claim for every token minted today). Null when signed out
  /// or when Firebase is not initialised (unit tests).
  static String? current([FirebaseAuth? auth]) {
    final User? user;
    try {
      user = (auth ?? FirebaseAuth.instance).currentUser;
    } catch (_) {
      return null;
    }
    if (user == null) return null;
    if (_cachedUid == user.uid && (_cachedDelegateId ?? '').isNotEmpty) {
      return _cachedDelegateId;
    }
    // Warm the cache for the next call; the uid is right until then.
    refresh(auth).ignore();
    return user.uid;
  }

  /// Reads the ID token claims, caches the result and returns the id.
  /// Falls back to the uid when the token cannot be read.
  static Future<String?> refresh([FirebaseAuth? auth]) async {
    final User? user;
    try {
      user = (auth ?? FirebaseAuth.instance).currentUser;
    } catch (_) {
      return null;
    }
    if (user == null) return null;
    try {
      final token = await user.getIdTokenResult();
      final id = fromClaims(uid: user.uid, claims: token.claims);
      remember(user.uid, id);
      return id;
    } catch (_) {
      return user.uid;
    }
  }

  /// Stores the id resolved for [uid] (after sign-in or a token refresh).
  static void remember(String uid, String? delegateId) {
    _cachedUid = uid;
    _cachedDelegateId = delegateId;
  }

  /// Every id that names the caller: the Auth uid and the delegate id.
  /// For comparisons that must accept both during phase 0.
  static Set<String> selfIds([FirebaseAuth? auth]) {
    String? uid;
    try {
      uid = (auth ?? FirebaseAuth.instance).currentUser?.uid;
    } catch (_) {
      uid = null;
    }
    final id = current(auth);
    return {if ((uid ?? '').isNotEmpty) uid!, if ((id ?? '').isNotEmpty) id!};
  }

  @visibleForTesting
  static void resetForTest() {
    _cachedUid = null;
    _cachedDelegateId = null;
  }
}
