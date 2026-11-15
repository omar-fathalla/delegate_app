import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firestore_resilience_helper.dart';

/// Loads the full `branches` collection at most once per signed-in session
/// and shares the result (including an in-flight load) between callers such
/// as [MarketingRemoteDataSource.getBranches] and the add-branch picker.
///
/// This removes repeated one-shot full-collection targets, which made the
/// Firestore web SDK watch-stream race (ca9/b815) much more likely.
class BranchesSessionCache {
  BranchesSessionCache._();

  static String? _sessionKey;
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _pending;

  /// Overridable session key provider (tests).
  @visibleForTesting
  static String? Function()? debugSessionKey;

  static String _currentKey(FirebaseFirestore firestore) {
    String? uid;
    try {
      uid = debugSessionKey != null
          ? debugSessionKey!()
          : FirebaseAuth.instance.currentUser?.uid;
    } catch (e, st) {
      debugPrint('BranchesSessionCache: session key lookup failed: $e\n$st');
      uid = null;
    }
    return '${identityHashCode(firestore)}:${uid ?? '-'}';
  }

  /// Returns the raw branch documents, loading them once per session.
  /// A failed load is not cached, so the next call retries.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> load(
    FirebaseFirestore firestore, {
    bool forceRefresh = false,
  }) {
    final key = _currentKey(firestore);
    if (forceRefresh || key != _sessionKey || _pending == null) {
      _sessionKey = key;
      final future = firestore
          .collection('branches')
          .getResilient(forceServer: true)
          .then((s) => s.docs);
      _pending = future;
      future.catchError((Object error, StackTrace stackTrace) {
        debugPrint('BranchesSessionCache: load failed: $error\n$stackTrace');
        if (identical(_pending, future)) _pending = null;
        Error.throwWithStackTrace(
          error is Exception ? error : Exception('$error'),
          stackTrace,
        );
      });
    }
    return _pending!;
  }

  /// Drops the cached list (call after creating/editing a branch or logout).
  static void invalidate() {
    _pending = null;
    _sessionKey = null;
  }
}
