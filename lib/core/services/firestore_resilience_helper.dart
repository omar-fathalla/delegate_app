import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Helper and extension providing Resilient Multi-Layered Firestore Architecture:
/// 1. Server-First with smart timeout and graceful Cache-Fallback
/// 2. Instant Cache Rendering (0 ms) with Live Background Synchronization (SWR)
/// 3. Hard Refresh & Invalidation for Pull-to-Refresh triggers
class FirestoreResilienceHelper {
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Executes a query trying the live server first.
  /// If the server doesn't respond within [timeout] or device is offline,
  /// it seamlessly falls back to the local Firestore cache.
  static Future<QuerySnapshot<T>> getResilientQuery<T>(
    Query<T> query, {
    Duration timeout = defaultTimeout,
    bool forceServer = true,
  }) async {
    if (forceServer) {
      try {
        final serverSnapshot = await query
            .get(const GetOptions(source: Source.server))
            .timeout(timeout);
        return serverSnapshot;
      } catch (e) {
        debugPrint('FirestoreResilienceHelper: Server query failed or timed out ($e). Falling back to local cache.');
        try {
          return await query.get(const GetOptions(source: Source.cache));
        } catch (cacheError) {
          debugPrint('FirestoreResilienceHelper: Cache query failed ($cacheError). Attempting default serverAndCache.');
          return await query.get(const GetOptions(source: Source.serverAndCache));
        }
      }
    } else {
      // Standard serverAndCache with fallback
      try {
        return await query.get(const GetOptions(source: Source.serverAndCache)).timeout(timeout);
      } catch (e) {
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
    if (forceServer) {
      try {
        return await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(timeout);
      } catch (e) {
        debugPrint('FirestoreResilienceHelper: Server doc query failed ($e). Falling back to local cache.');
        try {
          return await docRef.get(const GetOptions(source: Source.cache));
        } catch (cacheError) {
          return await docRef.get(const GetOptions(source: Source.serverAndCache));
        }
      }
    } else {
      try {
        return await docRef.get(const GetOptions(source: Source.serverAndCache)).timeout(timeout);
      } catch (e) {
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
    return query.snapshots(includeMetadataChanges: includeMetadataChanges);
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
