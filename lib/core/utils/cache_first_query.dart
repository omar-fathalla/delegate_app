import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Default freshness window for rarely-changing lists (branches, companies).
const Duration kStaticListTtl = Duration(hours: 6);

final Map<String, DateTime> _lastServerFetch = {};

/// Read-reduction Phase 4: cache-first read for static lists.
///
/// Within [ttl] of the last successful server read for [cacheKey] the query
/// is served from the local Firestore cache (0 billed reads). After the TTL,
/// when the cache is empty, or when the cache read fails, it hits the server.
Future<QuerySnapshot<T>> cacheFirstGet<T>(
  Query<T> query, {
  required String cacheKey,
  Duration ttl = kStaticListTtl,
  DateTime Function() now = DateTime.now,
}) async {
  final last = _lastServerFetch[cacheKey];
  if (last != null && now().difference(last) < ttl) {
    try {
      final cached = await query.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) return cached;
    } catch (_) {
      // Fall through to the server.
    }
  }
  final fresh = await query.get();
  if (!fresh.metadata.isFromCache) _lastServerFetch[cacheKey] = now();
  return fresh;
}

@visibleForTesting
void debugResetCacheFirst() => _lastServerFetch.clear();
