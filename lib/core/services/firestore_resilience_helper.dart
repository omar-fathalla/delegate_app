import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_client_health.dart';

/// Helper and extension providing Resilient Multi-Layered Firestore Architecture:
/// 1. Server-First with smart timeout and graceful Cache-Fallback
/// 2. Instant Cache Rendering (0 ms) with Live Background Synchronization (SWR)
/// 3. Hard Refresh & Invalidation for Pull-to-Refresh triggers
class FirestoreResilienceHelper {
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Cache fallback is for timeouts and offline, not for security denials.
  static bool isSecurityError(Object e) {
    return e is FirebaseException &&
        (e.code == 'permission-denied' || e.code == 'unauthenticated');
  }

  /// On web, Dart `.timeout` does not cancel the underlying JS `get`, so the
  /// old "server get -> on timeout start a cache get" pattern left two watch
  /// targets open on the same query. With many short-lived targets this
  /// triggers the Firestore JS SDK race (INTERNAL ASSERTION FAILED ca9 -> b815)
  /// that kills the client until reload. On web we therefore issue exactly one
  /// `get` at a time: a single `serverAndCache` get (the SDK itself falls back
  /// to cache when offline), and only after it has settled with an error do we
  /// try the cache. Mobile behaviour is unchanged.
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;

  static Future<S> _webSingleGet<S>(Future<S> Function(GetOptions) get) async {
    try {
      return await get(const GetOptions(source: Source.serverAndCache));
    } catch (e) {
      if (isSecurityError(e)) rethrow;
      if (FirestoreClientHealth.report(e)) rethrow; // dead client: don't retry
      // The first get has settled (failed), so there is no overlap now.
      debugPrint('FirestoreResilienceHelper(web): get failed ($e). Trying cache.');
      return await get(const GetOptions(source: Source.cache));
    }
  }

  /// Executes a query trying the live server first.
  /// If the server doesn't respond within [timeout] or device is offline,
  /// it seamlessly falls back to the local Firestore cache.
  static Future<QuerySnapshot<T>> getResilientQuery<T>(
    Query<T> query, {
    Duration timeout = defaultTimeout,
    bool forceServer = true,
  }) async {
    if (_isWeb) return _webSingleGet<QuerySnapshot<T>>(query.get);
    if (forceServer) {
      try {
        final serverSnapshot = await query
            .get(const GetOptions(source: Source.server))
            .timeout(timeout);
        return serverSnapshot;
      } catch (e) {
        if (isSecurityError(e)) rethrow;
        debugPrint('FirestoreResilienceHelper: Server query failed or timed out ($e). Falling back to local cache.');
        try {
          return await query.get(const GetOptions(source: Source.cache));
        } catch (cacheError) {
          if (isSecurityError(cacheError)) rethrow;
          debugPrint('FirestoreResilienceHelper: Cache query failed ($cacheError). Attempting default serverAndCache.');
          return await query.get(const GetOptions(source: Source.serverAndCache));
        }
      }
    } else {
      // Standard serverAndCache with fallback
      try {
        return await query.get(const GetOptions(source: Source.serverAndCache)).timeout(timeout);
      } catch (e) {
        if (isSecurityError(e)) rethrow;
        return await query.get(const GetOptions(source: Source.cache));
      }
    }
  }

  /// Executes a document lookup trying the live server first with cache fallback.
  static Future<DocumentSnapshot<T>> getResilientDoc<T>(
    DocumentReference<T> docRef, {
    Duration timeout = defaultTimeout,
    bool forceServer = true,
  }) async {
    if (_isWeb) return _webSingleGet<DocumentSnapshot<T>>(docRef.get);
    if (forceServer) {
      try {
        return await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(timeout);
      } catch (e) {
        if (isSecurityError(e)) rethrow;
        debugPrint('FirestoreResilienceHelper: Server doc query failed ($e). Falling back to local cache.');
        try {
          return await docRef.get(const GetOptions(source: Source.cache));
        } catch (cacheError) {
          if (isSecurityError(cacheError)) rethrow;
          return await docRef.get(const GetOptions(source: Source.serverAndCache));
        }
      }
    } else {
      try {
        return await docRef.get(const GetOptions(source: Source.serverAndCache)).timeout(timeout);
      } catch (e) {
        if (isSecurityError(e)) rethrow;
        return await docRef.get(const GetOptions(source: Source.cache));
      }
    }
  }

  /// Provides an SWR (Stale-While-Revalidate) resilient stream:
  /// - Emits cached snapshot immediately if available
  /// - Listens for server metadata and updates continuously
  static Stream<QuerySnapshot<T>> streamResilient<T>(
    Query<T> query, {
    bool includeMetadataChanges = true,
  }) {
    return query
        .snapshots(includeMetadataChanges: includeMetadataChanges)
        .handleError((Object e, StackTrace st) {
      FirestoreClientHealth.report(e);
      Error.throwWithStackTrace(e, st);
    });
  }
}

/// Extension methods for clean, expressive usage on any Query or DocumentReference
extension FirestoreQueryResilienceExtension<T> on Query<T> {
  Future<QuerySnapshot<T>> getResilient({
    Duration timeout = FirestoreResilienceHelper.defaultTimeout,
    bool forceServer = true,
  }) {
    return FirestoreResilienceHelper.getResilientQuery(
      this,
      timeout: timeout,
      forceServer: forceServer,
    );
  }

  Stream<QuerySnapshot<T>> streamResilient({bool includeMetadataChanges = true}) {
    return FirestoreResilienceHelper.streamResilient(
      this,
      includeMetadataChanges: includeMetadataChanges,
    );
  }
}

extension FirestoreDocResilienceExtension<T> on DocumentReference<T> {
  Future<DocumentSnapshot<T>> getResilient({
    Duration timeout = FirestoreResilienceHelper.defaultTimeout,
    bool forceServer = true,
  }) {
    return FirestoreResilienceHelper.getResilientDoc(
      this,
      timeout: timeout,
      forceServer: forceServer,
    );
  }
}
